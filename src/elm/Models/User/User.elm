-- Module for the user model
module Models.User.User exposing(..)

import Json.Decode as JsonDecode exposing (..)
import Json.Decode.Pipeline exposing (..)
import Json.Encode as Encode
import List.Extra as ListExtra
import Models.MembershipPlan.Subscription as Subscription
import Models.Page as Page
import Models.Payment.PaymentMethod as PaymentMethod
import Models.Role as Role
import Time exposing (..)


type alias Model =
    { id: Int
    , name: String
    , email: String
    , password: String
    , stripe_customer_key: Maybe String
    , payment_methods: List PaymentMethod.Model
    , roles: List Role.Model
    , subscriptions: List Subscription.Model
    }


type alias Page =
    Page.Model Model


loginModel : String -> String -> Model
loginModel email password =
    { id = 0
    , name = ""
    , email = email
    , password = password
    , stripe_customer_key = Nothing
    , payment_methods = []
    , roles = []
    , subscriptions = []
    }


-- Role Helpers
canViewArticles : Model -> Bool
canViewArticles user =
    List.any (hasRole user) [Role.superAdmin, Role.articleViewer, Role.articleEditor]


isAdmin : Model -> Bool
isAdmin user =
    hasRole user Role.superAdmin


hasRole : Model -> Int -> Bool
hasRole user roleId =
    List.any (\role -> roleId == role.id) user.roles


-- adds the passed in role to the user model
addRole : Model -> Role.Model -> Model
addRole user role =
    { user
        | roles = List.append user.roles [role]
    }


-- removes a role from a user model
removeRole : Model -> Role.Model -> Model
removeRole user role =
    { user
        | roles = ListExtra.remove role user.roles
    }


-- Subscription Helpers
getActiveSubscriptions : Posix -> Model -> List Subscription.Model
getActiveSubscriptions now model =
    List.filter (Subscription.isActive now) model.subscriptions


getCurrentSubscription : Posix -> Model -> Maybe Subscription.Model
getCurrentSubscription now model =
    List.head
        <| List.sortWith Subscription.compareExpiration (getActiveSubscriptions now model)


-- Converts a user model into a JSON string
toJson : Model -> Encode.Value
toJson model =
    Encode.object
        <| List.concat
            [ if String.length model.email > 0 then
                [ ("email", Encode.string model.email) ]
            else
                []
            , if String.length model.password > 0 then
                [ ("password", Encode.string model.password) ]
            else
                []
            , if String.length model.name > 0 then
                [ ("name", Encode.string model.name) ]
            else
                []
            , if List.length model.roles > 0 then
                [ ("roles", Encode.list Encode.int  (List.map (\role -> role.id) model.roles)) ]
            else
                []
            ]


cacheEncoder : Model -> Encode.Value
cacheEncoder model =
    Encode.object <| List.concat
        [
          [ ( "id" , Encode.int model.id)
          , ("name", Encode.string model.name)
          , ("email", Encode.string model.email)
          ]
        , case model.stripe_customer_key of
            Just stripe_customer_key ->
                [("stripe_customer_key", Encode.string stripe_customer_key)]
            Nothing ->
                []
        , [ ("roles", (Encode.list Role.cacheEncoder) model.roles)
          ]
        ]


-- Decodes a user model retrieved through the API
modelDecoder : Decoder Model
modelDecoder =
    JsonDecode.succeed Model
        |> required "id" int
        |> required "name" string
        |> required "email" string
        |> hardcoded ""
        |> optional "stripe_customer_key" (maybe string) Nothing
        |> optional "payment_methods" PaymentMethod.listDecoder []
        |> optional "roles" Role.listDecoder []
        |> optional "subscriptions" Subscription.listDecoder []


listDecoder : Decoder (List Model)
listDecoder =
    JsonDecode.list modelDecoder


pageDecoder : Decoder Page
pageDecoder =
    Page.modelDecoder listDecoder
