(ns status-im.ui.components.invite.views
  (:require [quo.core :as quo]
            [reagent.core :as reagent]
            [re-frame.core :as re-frame]
            [status-im.ui.components.list-item.views :as list-item]
            [status-im.ui.components.chat-icon.screen :as chat-icon]
            [status-im.ui.components.toolbar :as toolbar]
            [status-im.ui.components.bottom-sheet.view :as bottom-sheet]
            [status-im.utils.utils :as utils]
            [status-im.i18n :as i18n]
            [status-im.ui.components.invite.events :as events]
            [quo.react-native :as rn]))

;; Select account sheet
(defn render-account [current-account change-account]
  (fn [account]
    [list-item/list-item
     {:theme     :selectable
      :selected? (= (:address current-account) (:address account))
      :icon      [chat-icon/custom-icon-view-list (:name account) (:color account)]
      :title     (:name account)
      :subtitle  (utils/get-shortened-checksum-address (:address account))
      :on-press  #(change-account account)}]))

(defn accounts-list [accounts current-account change-account]
  (fn []
    [rn/view {:flex 1}
     [quo/text {:align :center
                :style {:padding-horizontal 16}}
      "Select an account to receive your referral bonus"]
     [rn/flat-list {:data      accounts
                    :key-fn    :address
                    :render-fn (render-account current-account change-account)}]]))

;; Invite sheet

(defn- step [{:keys [number description]}]
  [rn/view {:style {:flex-direction   :row
                    :padding-vertical 12
                    :flex             1
                    :align-items      :center}}
   [rn/view {:style {:width           40
                     :height          40
                     :border-radius   20
                     :border-width    1
                     :justify-content :center
                     :align-items     :center
                     :border-color    "#EEF2F5"}}
    [quo/text {:weight :bold
               :size   :large}
     number]]
   [rn/view {:padding-left 16
             :flex         1}
    [quo/text {}
     description]]])

(def steps-values [{:number      1
                    :description "You send a unique invite link to your friend to download and join Status"}
                   {:number      2
                    :description "Your friend downloads Status and creates an account"}
                   {:number      3
                    :description "Your friend buys a Starter Pack on any Android device. Sorry, no iOS!"}
                   {:number      4
                    :description "You receive your referral bonus"}])

(defn referral-steps []
  [rn/view {:style {:padding-vertical    8
                    :padding-horizontal  16
                    :border-bottom-width 1
                    :border-bottom-color "#EEF2F5"}}
   [rn/view {:style {:padding-top    14
                     :padding-bottom 4}}
    [quo/text {:color :secondary}
     "How it works"]]
   [rn/view {:flex 1}
    (for [s steps-values]
      [step s])]])

(defn referral-account []
  (let [visible (reagent/atom false)]
    (fn [{:keys [account accounts change-account]}]
      [rn/view {:style {:padding-vertical 8}}
       [rn/view {:style {:padding-horizontal 16}}
        [quo/text {}
         "Account to receive your referral bonus"]]
       [rn/modal {:visible     @visible
                  :transparent true}
        [bottom-sheet/bottom-sheet {:show?     true
                                    :on-cancel #(reset! visible false)
                                    :content   (accounts-list accounts account
                                                              change-account)}]]
       [list-item/list-item
        {:theme    :selectable
         :icon     [chat-icon/custom-icon-view-list (:name account) (:color account)]
         :title    (:name account)
         :subtitle (utils/get-shortened-checksum-address (:address account))
         :on-press #(reset! visible true)}]])))

(defn referral-sheet- []
  (let [account* (reagent/atom nil)]
   (fn []
     (let [accounts        @(re-frame/subscribe [:accounts-without-watch-only])
           default-account @(re-frame/subscribe [:default-account]) ; FIXME:
           account         (or @account* default-account)]
       [rn/view {:flex 1}
        [referral-steps]
        [referral-account {:account        @account
                           :change-account #(reset! account %)
                           :accounts       accounts}]
        [toolbar/toolbar {:show-border? true
                          :center       {:label    "Invite"
                                         :type     :secondary
                                         :on-press #(re-frame/dispatch [::events/generate-invite
                                                                        {:address (get @account :address)}])}}]]))))

(defn referral-sheet []
  [bottom-sheet/bottom-sheet {:content referral-sheet-
                              :show?   true}])
