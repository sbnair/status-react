(ns status-im.multiaccounts.recover.core
  (:require [clojure.string :as string]
            [re-frame.core :as re-frame]
            [status-im.constants :as constants]
            [status-im.ethereum.core :as ethereum]
            [status-im.ethereum.mnemonic :as mnemonic]
            [status-im.hardwallet.nfc :as nfc]
            [status-im.i18n :as i18n]
            [status-im.multiaccounts.create.core :as multiaccounts.create]
            [status-im.native-module.core :as status]
            [status-im.popover.core :as popover]
            [status-im.navigation :as navigation]
            [status-im.utils.fx :as fx]
            [status-im.utils.security :as security]
            [status-im.utils.types :as types]
            [status-im.utils.platform :as platform]
            [status-im.utils.utils :as utils]
            [status-im.ui.components.bottom-sheet.core :as bottom-sheet]
            [taoensso.timbre :as log]
            [status-im.utils.config :as config]))

(defn existing-account?
  [multiaccounts key-uid]
  {:pre [(not (nil? key-uid))]}
  (contains? multiaccounts key-uid))

(re-frame/reg-fx
 ::validate-mnemonic
 (fn [[passphrase callback]]
   (status/validate-mnemonic passphrase callback)))

(defn check-phrase-warnings [recovery-phrase]
  (cond (string/blank? recovery-phrase) :t/required-field))

(fx/defn set-phrase
  {:events [:multiaccounts.recover/passphrase-input-changed]}
  [{:keys [db]} masked-recovery-phrase]
  (let [recovery-phrase (security/safe-unmask-data masked-recovery-phrase)]
    (fx/merge
     {:db (update db :intro-wizard assoc
                  :passphrase (string/lower-case recovery-phrase)
                  :passphrase-error nil
                  :next-button-disabled? (or (empty? recovery-phrase)
                                             (not (mnemonic/valid-length? recovery-phrase))))})))

(fx/defn validate-phrase-for-warnings
  [{:keys [db]}]
  (let [recovery-phrase (get-in db [:intro-wizard :passphrase])]
    {:db (update db :intro-wizard assoc
                 :passphrase-error (check-phrase-warnings recovery-phrase))}))

(fx/defn on-store-multiaccount-success
  {:events       [::store-multiaccount-success]
   :interceptors [(re-frame/inject-cofx :random-guid-generator)
                  (re-frame/inject-cofx ::multiaccounts.create/get-signing-phrase)]}
  [{:keys [db] :as cofx} result password]
  (let [{:keys [error]} (types/json->clj result)]
    (if error
      {:utils/show-popup {:title      (i18n/label :t/multiaccount-exists-title)
                          :content    (i18n/label :t/multiaccount-exists-title)
                          :on-dismiss #(re-frame/dispatch [:navigate-to :multiaccounts])}}
      (let [{:keys [key-uid] :as multiaccount} (get-in db [:intro-wizard :root-key])
            keycard-multiaccount? (boolean (get-in db [:multiaccounts/multiaccounts key-uid :keycard-pairing]))]
        (if keycard-multiaccount?
          ;; trying to recover multiaccount created with keycard
          {:db        (-> db
                          (update :intro-wizard assoc
                                  :processing? false
                                  :passphrase-error :recover-keycard-multiaccount-not-supported)
                          (update :intro-wizard dissoc
                                  :passphrase-valid?))}
          (let [multiaccount (assoc multiaccount :derived (get-in db [:intro-wizard :derived]))]
            (multiaccounts.create/on-multiaccount-created cofx
                                                          multiaccount
                                                          password
                                                          {})))))))

(fx/defn store-multiaccount
  {:events [::recover-multiaccount-confirmed]}
  [{:keys [db]}]
  (let [password (get-in db [:intro-wizard :key-code])
        {:keys [root-key]} (:intro-wizard db)
        {:keys [id]} root-key
        callback #(re-frame/dispatch [::store-multiaccount-success % password])
        hashed-password (ethereum/sha3 (security/safe-unmask-data password))]
    {:db (assoc-in db [:intro-wizard :processing?] true)
     ::multiaccounts.create/store-multiaccount [id hashed-password callback]}))

(fx/defn recover-multiaccount-with-checks
  {:events [::sign-in-button-pressed]}
  [{:keys [db] :as cofx}]
  (let [{:keys [passphrase processing?]} (:intro-wizard db)]
    (when-not processing?
      (if (mnemonic/status-generated-phrase? passphrase)
        (store-multiaccount cofx)
        {:ui/show-confirmation
         {:title               (i18n/label :recovery-typo-dialog-title)
          :content             (i18n/label :recovery-typo-dialog-description)
          :confirm-button-text (i18n/label :recovery-confirm-phrase)
          :on-accept           #(re-frame/dispatch [::recover-multiaccount-confirmed])}}))))

(re-frame/reg-fx
 ::import-multiaccount
 (fn [{:keys [passphrase password]}]
   (log/debug "[recover] ::import-multiaccount")
   (status/multiaccount-import-mnemonic
    passphrase
    password
    (fn [result]
      (let [{:keys [id] :as root-data}
            (multiaccounts.create/normalize-multiaccount-data-keys
             (types/json->clj result))]
        (status-im.native-module.core/multiaccount-derive-addresses
         id
         [constants/path-wallet-root
          constants/path-eip1581
          constants/path-whisper
          constants/path-default-wallet]
         (fn [result]
           (let [derived-data (multiaccounts.create/normalize-derived-data-keys
                               (types/json->clj result))
                 public-key (get-in derived-data [constants/path-whisper-keyword :public-key])]
             (status/gfycat-identicon-async
              public-key
              (fn [name photo-path]
                (let [derived-data-extended
                      (update derived-data
                              constants/path-whisper-keyword
                              merge {:name name :photo-path photo-path})]
                  (re-frame/dispatch [::import-multiaccount-success
                                      root-data derived-data-extended]))))))))))))

(fx/defn show-existing-multiaccount-alert
  [_ key-uid]
  {:utils/show-confirmation
   {:title               (i18n/label :t/multiaccount-exists-title)
    :content             (i18n/label :t/multiaccount-exists-content)
    :confirm-button-text (i18n/label :t/unlock)
    :on-accept           #(re-frame/dispatch
                           [:multiaccounts.login.ui/multiaccount-selected key-uid])
    :on-cancel           #(re-frame/dispatch [:navigate-to :multiaccounts])}})

(fx/defn on-import-multiaccount-success
  {:events [::import-multiaccount-success]}
  [{:keys [db] :as cofx} {:keys [key-uid] :as root-data} derived-data]
  (let [multiaccounts (:multiaccounts/multiaccounts db)]
    (fx/merge
     cofx
     {:db (update db :intro-wizard
                  assoc :root-key root-data
                  :derived derived-data
                  :step :recovery-success
                  :forward-action :multiaccounts.recover/re-encrypt-pressed)}
     (when (existing-account? multiaccounts key-uid)
       (show-existing-multiaccount-alert key-uid))
     (navigation/navigate-to-cofx :recover-multiaccount-success nil))))

(fx/defn enter-phrase-pressed
  {:events [::enter-phrase-pressed]}
  [{:keys [db] :as cofx}]
  (fx/merge
   cofx
   {:db (-> db
            (assoc :intro-wizard
                   {:step                   :enter-phrase
                    :recovering?            true
                    :next-button-disabled?  true
                    :weak-password?         true
                    :encrypt-with-password? true
                    :back-action            :intro-wizard/navigate-back
                    :forward-action         :multiaccounts.recover/enter-phrase-next-pressed})
            (update :hardwallet dissoc :flow))}
   (bottom-sheet/hide-bottom-sheet)
   (navigation/navigate-to-cofx :recover-multiaccount-enter-phrase nil)))

(fx/defn proceed-to-import-mnemonic
  {:events [:multiaccounts.recover/phrase-validated]}
  [{:keys [db] :as cofx} phrase-warnings]
  (let [{:keys [password passphrase]} (:intro-wizard db)]
    (if-not (string/blank? (:error (types/json->clj phrase-warnings)))
      (popover/show-popover cofx {:view :custom-seed-phrase})
      (when (mnemonic/valid-length? passphrase)
        {::import-multiaccount {:passphrase (mnemonic/sanitize-passphrase passphrase)
                                :password   password}}))))

(fx/defn seed-phrase-next-pressed
  {:events [:multiaccounts.recover/enter-phrase-next-pressed]}
  [{:keys [db] :as cofx}]
  (let [{:keys [passphrase]} (:intro-wizard db)]
    {::validate-mnemonic [passphrase #(re-frame/dispatch [:multiaccounts.recover/phrase-validated %])]}))

(fx/defn continue-to-import-mnemonic
  {:events [::continue-pressed]}
  [{:keys [db] :as cofx}]
  (let [{:keys [password passphrase]} (:multiaccounts/recover db)]
    (fx/merge cofx
              {::import-multiaccount {:passphrase passphrase
                                      :password   password}}
              (popover/hide-popover))))

(fx/defn dec-step
  {:events [:multiaccounts.recover/dec-step]}
  [{:keys [db] :as cofx}]
  (let [step (get-in db [:intro-wizard :step])]
    (if (= step :enter-phrase)
      {:db (dissoc db :intro-wizard)}
      {:db (update db :intro-wizard assoc :step
                   (case step
                     :recovery-success :enter-phrase
                     :select-key-storage :recovery-success
                     :create-code :select-key-storage
                     :confirm-code :create-code)
                   :confirm-failure? false
                   :key-code nil
                   :weak-password? true)})))

(fx/defn cancel-pressed
  {:events [:multiaccounts.recover/cancel-pressed]}
  [{:keys [db] :as cofx} skip-alert?]
  ;; Workaround for multiple Cancel button clicks
  ;; that can break navigation tree
  (let [step (get-in db [:intro-wizard :step])]
    (when-not (#{:multiaccounts :login} (:view-id db))
      (if (and (= step :select-key-storage) (not skip-alert?))
        (utils/show-question
         (i18n/label :t/are-you-sure-to-cancel)
         (i18n/label :t/you-will-start-from-scratch)
         #(re-frame/dispatch [:multiaccounts.recover/cancel-pressed true]))
        (fx/merge cofx
                  dec-step
                  navigation/navigate-back)))))

(fx/defn select-storage-next-pressed
  {:events       [:multiaccounts.recover/select-storage-next-pressed]
   :interceptors [(re-frame/inject-cofx :random-guid-generator)]}
  [{:keys [db] :as cofx}]
  (let [storage-type (get-in db [:intro-wizard :selected-storage-type])]
    (if (= storage-type :advanced)
      ;;TODO: fix circular dependency to remove dispatch here
      {:dispatch [:recovery.ui/keycard-option-pressed]}
      (fx/merge cofx
                {:db (update db :intro-wizard assoc :step :create-code
                             :forward-action :multiaccounts.recover/enter-password-next-pressed)}
                (navigation/navigate-to-cofx :recover-multiaccount-enter-password nil)))))

(fx/defn re-encrypt-pressed
  {:events [:multiaccounts.recover/re-encrypt-pressed]}
  [{:keys [db] :as cofx}]
  (fx/merge cofx
            {:db (update db :intro-wizard
                         assoc :step :select-key-storage
                         :forward-action :multiaccounts.recover/select-storage-next-pressed
                         :selected-storage-type :default)}
            (if (and (or platform/android?
                         config/keycard-test-menu-enabled?)
                     (nfc/nfc-supported?))
              (navigation/navigate-to-cofx :recover-multiaccount-select-storage nil)
              (select-storage-next-pressed))))

(fx/defn proceed-to-password-confirm
  [{:keys [db] :as cofx}]
  (fx/merge cofx
            {:db  (update db :intro-wizard assoc :step :confirm-code
                          :forward-action :multiaccounts.recover/confirm-password-next-pressed)}
            (navigation/navigate-to-cofx :recover-multiaccount-confirm-password nil)))

(fx/defn enter-password-next-button-pressed
  {:events [:multiaccounts.recover/enter-password-next-pressed]}
  [{:keys [db] :as cofx}]
  (fx/merge cofx
            {:db (-> db
                     (assoc-in [:intro-wizard :stored-key-code] (get-in db [:intro-wizard :key-code]))
                     (assoc-in [:intro-wizard :key-code] ""))}
            (proceed-to-password-confirm)))

(fx/defn confirm-password-next-button-pressed
  {:events [:multiaccounts.recover/confirm-password-next-pressed]
   :interceptors [(re-frame/inject-cofx :random-guid-generator)]}
  [{:keys [db] :as cofx}]
  (let [{:keys [key-code stored-key-code]} (:intro-wizard db)]
    (if (= key-code stored-key-code)
      (fx/merge cofx
                (store-multiaccount))
      {:db (assoc-in db [:intro-wizard :confirm-failure?] true)})))

(fx/defn count-words
  [{:keys [db]}]
  (let [passphrase (get-in db [:intro-wizard :passphrase])]
    {:db (assoc-in db [:intro-wizard :passphrase-word-count]
                   (mnemonic/words-count passphrase))}))

(fx/defn run-validation
  [{:keys [db] :as cofx}]
  (let [passphrase (get-in db [:intro-wizard :passphrase])]
    (when (= (last passphrase) " ")
      (fx/merge cofx
                (validate-phrase-for-warnings)))))

(fx/defn enter-phrase-input-changed
  {:events [:multiaccounts.recover/enter-phrase-input-changed]}
  [cofx input]
  (fx/merge cofx
            (set-phrase input)
            (count-words)
            (run-validation)))
