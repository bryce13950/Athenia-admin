module Page.Admin.Sections.User exposing (..)

import Api exposing (Token)
import Components.CRUD.ModelForm.Input as Input
import Components.CRUD.ModelForm.TextField as TextField
import Components.CRUD.ModelForm as ModelForm
import Components.CRUD.ModelList as ModelList
import Components.CRUD.RootController as RootController
import Components.CRUD.SharedConfiguration as SharedConfiguration
import Components.Entity.SubscriptionHistory as SubscriptionHistory
import Html exposing (..)
import Models.User.User as User
import Utilities.SearchField exposing (SearchFieldType(..))
import Utilities.ModelHelpers exposing (..)


type alias Model =
    RootController.Model User.Model FormModel FormMsg


type alias Msg =
    RootController.Msg User.Model FormMsg


type alias FormModel =
    { apiUrl: String
    , first_name: String
    , last_name: String
    , email: String
    , password: String
    , subscriptionHistory: Maybe SubscriptionHistory.Model
    }

type FormMsg
    = SetFirstName String
    | SetLastName String
    | SetEmail String
    | SetPassword String
    | SubscriptionHistoryMsg SubscriptionHistory.Msg


sharedConfiguration: String -> SharedConfiguration.Configuration User.Model
sharedConfiguration apiUrl =
    SharedConfiguration.configure apiUrl "User" "users" (User.routeGroup apiUrl) User.modelDecoder []


firstNameColumn: ModelList.Column User.Model
firstNameColumn =
     ModelList.column
        "First Name"
        (\user -> Html.text user.first_name)
        "first_name"
        Text

lastNameColumn: ModelList.Column User.Model
lastNameColumn =
     ModelList.column
        "Last Name"
        (\user -> Html.text user.last_name)
        "last_name"
        Text


emailColumn: ModelList.Column User.Model
emailColumn =
     ModelList.column
        "Email"
        (\user -> Html.text user.email)
        "email"
        Text


indexColumns: List (ModelList.Column User.Model)
indexColumns =
    [ firstNameColumn
    , lastNameColumn
    , emailColumn
    ]


indexConfiguration: ModelList.Configuration User.Model
indexConfiguration =
    ModelList.configure [] indexColumns


validateForm: User.Model -> FormModel -> Result String User.Model
validateForm model form =
    if String.length form.email < 1 then
        Err "Please enter users email address"
    else
        Ok { model
            | first_name = form.first_name
            , last_name = form.last_name
            , email = form.email
            , password = form.password
           }


initForm: String -> Token -> (FormModel, Cmd FormMsg)
initForm apiUrl _ =
    ( { apiUrl = apiUrl
      , first_name = ""
      , last_name = ""
      , email = ""
      , password = ""
      , subscriptionHistory = Nothing
    }
    , Cmd.none
    )


updateForm: Token -> User.Model -> FormMsg -> FormModel -> (FormModel, Cmd FormMsg)
updateForm token dataModel msg model =
    case msg of
        SetFirstName firstName ->
            ( { model
                | first_name = firstName
            }
            , Cmd.none
            )

        SetLastName lastName ->
            ( { model
                | last_name = lastName
            }
            , Cmd.none
            )

        SetEmail email ->
            ( { model
                | email = email
            }
            , Cmd.none
            )

        SetPassword password ->
            ( { model
                | password = password
            }
            , Cmd.none
            )

        SubscriptionHistoryMsg subMsg ->
            case model.subscriptionHistory of
                Just subscriptionHistory ->
                    let
                        (updatedSubscriptionHistory, subscriptionHistoryCmd) =
                            SubscriptionHistory.update token subMsg subscriptionHistory
                    in
                    ( { model
                        | subscriptionHistory = Just updatedSubscriptionHistory
                    }
                    , Cmd.map SubscriptionHistoryMsg subscriptionHistoryCmd
                    )

                Nothing ->
                    (model, Cmd.none)


setModel: Token -> GenericModel User.Model -> FormModel -> (FormModel, Cmd FormMsg)
setModel token dataModel model =
    let
        (subscriptionHistory, subscriptionCmd) =
            case dataModel.id of
                Just id ->
                    Tuple.mapFirst Just
                        <| SubscriptionHistory.initialModel token model.apiUrl "users" id

                Nothing ->
                    (Nothing, Cmd.none)

    in
    ( { model
      | first_name = dataModel.first_name
      , last_name = dataModel.last_name
      , email = dataModel.email
      , subscriptionHistory = subscriptionHistory
    }
    , Cmd.map SubscriptionHistoryMsg subscriptionCmd
    )


firstNameInput: Bool -> FormModel -> Html FormMsg
firstNameInput isLoading model =
    TextField.view (Input.configure True "First Name" "first_name") model.first_name SetFirstName isLoading


lastNameInput: Bool -> FormModel -> Html FormMsg
lastNameInput isLoading model =
    TextField.view (Input.configure True "Last Name" "last_name") model.last_name SetLastName isLoading


emailInput: Bool -> FormModel -> Html FormMsg
emailInput isLoading model =
    TextField.view (Input.configure True "Email" "email") model.email SetEmail isLoading


passwordInput: Bool -> FormModel -> Html FormMsg
passwordInput isLoading model =
    TextField.view (Input.configure True "Password (leave blank to keep current password)" "password") model.password SetPassword isLoading


subscriptionHistoryView: Bool -> FormModel -> Html FormMsg
subscriptionHistoryView _ model =
    case model.subscriptionHistory of
        Just subscriptionHistory ->
            Html.map SubscriptionHistoryMsg
                <| SubscriptionHistory.view subscriptionHistory

        Nothing ->
            text ""


baseFormConfig: ModelForm.Configuration User.Model FormModel FormMsg
baseFormConfig =
    ModelForm.configure User.toJson User.toJson User.newModel validateForm initForm updateForm


formConfiguration: ModelForm.Configuration User.Model FormModel FormMsg
formConfiguration =
    ModelForm.addFields (ModelForm.configureSetModelAction setModel baseFormConfig)
        [ firstNameInput
        , lastNameInput
        , emailInput
        , passwordInput
        , subscriptionHistoryView
        ]


configuration: String -> RootController.Configuration User.Model FormModel FormMsg
configuration apiUrl =
    RootController.configure (sharedConfiguration apiUrl) indexConfiguration formConfiguration


initialModel: String -> RootController.Model User.Model FormModel FormMsg
initialModel apiUrl =
    RootController.initialState
        <| configuration apiUrl
