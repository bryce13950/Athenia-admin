module Athenia.Page.Login exposing (Model, Msg, init, subscriptions, toSession, update, view)

{-| The login page.
-}

import Athenia.Api as Api exposing (Token)
import Athenia.Models.User.User as User
import Athenia.Route as Route exposing (Route)
import Athenia.Session as Session exposing (Session)
import Athenia.Viewer as Viewer exposing (Viewer)
import Browser.Navigation as Nav
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Http
import Json.Decode as Decode exposing (Decoder, decodeString, field, string)
import Json.Decode.Pipeline exposing (optional)
import Json.Encode as Encode



-- MODEL


type alias Model =
    { session : Session
    , problems : List Problem
    , user : User.Model
    }


{-| Recording validation problems on a per-field basis facilitates displaying
them inline next to the field where the error occurred.

I implemented it this way out of habit, then realized the spec called for
displaying all the errors at the top. I thought about simplifying it, but then
figured it'd be useful to show how I would normally model this data - assuming
the intended UX was to render errors per field.

(The other part of this is having a view function like this:

viewFieldErrors : ValidatedField -> List Problem -> Html msg

...and it filters the list of problems to render only InvalidEntry ones for the
given ValidatedField. That way you can call this:

viewFieldErrors Email problems

...next to the `email` field, and call `viewFieldErrors Password problems`
next to the `password` field, and so on.

The `LoginError` should be displayed elsewhere, since it doesn't correspond to
a particular field.

-}
type Problem
    = InvalidEntry ValidatedField String
    | ServerError String


init : Session -> ( Model, Cmd msg )
init session =
    ( { session = session
      , problems = []
      , user =
        User.loginModel "" ""
      }
    , Cmd.none
    )



-- VIEW


view : Model -> { title : String, content : Html Msg }
view model =
    { title = "Login"
    , content =
        div [ class "cred-page" ]
            [ div [ class "container page" ]
                [ div [ class "row" ]
                    [ div [ class "col-md-6 offset-md-3 col-xs-12" ]
                        [ h1 [ class "text-xs-center" ] [ text "Sign in" ]
                        , p [ class "text-xs-center" ]
                            [ a [ Route.href Route.Register ]
                                [ text "Need an account?" ]
                            ]
                        , ul [ class "error-messages" ]
                            (List.map viewProblem model.problems)
                        , viewForm model.user
                        ]
                    ]
                ]
            ]
    }


viewProblem : Problem -> Html msg
viewProblem problem =
    let
        errorMessage =
            case problem of
                InvalidEntry _ str ->
                    str

                ServerError str ->
                    str
    in
    li [] [ text errorMessage ]


viewForm : User.Model -> Html Msg
viewForm user =
    Html.form [ onSubmit SubmittedForm ]
        [ fieldset [ class "form-group" ]
            [ input
                [ class "form-control form-control-lg"
                , placeholder "Email"
                , onInput EnteredEmail
                , value user.email
                ]
                []
            ]
        , fieldset [ class "form-group" ]
            [ input
                [ class "form-control form-control-lg"
                , type_ "password"
                , placeholder "Password"
                , onInput EnteredPassword
                , value user.password
                ]
                []
            ]
        , button [ class "btn btn-lg btn-primary pull-xs-right" ]
            [ text "Sign in" ]
        ]



-- UPDATE


type Msg
    = SubmittedForm
    | EnteredEmail String
    | EnteredPassword String
    | CompletedLogin (Result Http.Error Api.Token)
    | RetrieveMe Token (Result Http.Error User.Model)
    | GotSession Session


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SubmittedForm ->
            case validate model.user of
                Ok validForm ->
                    ( { model | problems = [] }
                    , Http.send CompletedLogin (login validForm)
                    )

                Err problems ->
                    ( { model | problems = problems }
                    , Cmd.none
                    )

        EnteredEmail email ->
            updateForm (\user -> { user | email = email }) model

        EnteredPassword password ->
            updateForm (\user -> { user | password = password }) model

        CompletedLogin (Err error) ->
            handleErrors error model

        CompletedLogin (Ok token) ->
            ( model
            , Http.send (RetrieveMe token) (getMe token)
            )

        GotSession session ->
            ( { model | session = session }
            , Route.replaceUrl (Session.navKey session) Route.Home
            )

        RetrieveMe token (Err error) ->
            handleErrors error model

        RetrieveMe token (Ok user) ->
            ( model
            , Viewer.store
                <| Viewer.viewer user token
            )


{-| Helper function for `update`. Updates the form and returns Cmd.none.
Useful for recording form fields!
-}
updateForm : (User.Model -> User.Model) -> Model -> ( Model, Cmd Msg )
updateForm transform model =
    ( { model | user = transform model.user }, Cmd.none )


handleErrors : Http.Error -> Model -> (Model, Cmd Msg)
handleErrors errors model =
    let
        serverErrors =
            Api.decodeErrors errors
                |> List.map ServerError
    in
    ( { model | problems = List.append model.problems serverErrors }
    , Cmd.none
    )

-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Session.changes GotSession (Session.navKey model.session)



-- FORM


{-| Marks that we've trimmed the form's fields, so we don't accidentally send
it to the server without having trimmed it!
-}
type TrimmedUser
    = Trimmed User.Model


{-| When adding a variant here, add it to `fieldsToValidate` too!
-}
type ValidatedField
    = Email
    | Password


fieldsToValidate : List ValidatedField
fieldsToValidate =
    [ Email
    , Password
    ]


{-| Trim the form and validate its fields. If there are problems, report them!
-}
validate : User.Model -> Result (List Problem) TrimmedUser
validate user =
    let
        trimmedForm =
            trimFields user
    in
    case List.concatMap (validateField trimmedForm) fieldsToValidate of
        [] ->
            Ok trimmedForm

        problems ->
            Err problems


validateField : TrimmedUser -> ValidatedField -> List Problem
validateField (Trimmed user) field =
    List.map (InvalidEntry field) <|
        case field of
            Email ->
                if String.isEmpty user.email then
                    [ "email can't be blank." ]

                else
                    []

            Password ->
                if String.isEmpty user.password then
                    [ "password can't be blank." ]

                else
                    []


{-| Don't trim while the user is typing! That would be super annoying.
Instead, trim only on submit.
-}
trimFields : User.Model -> TrimmedUser
trimFields user =
    Trimmed
        <| User.loginModel
            (String.trim user.email)
            (String.trim user.password)



-- HTTP


login : TrimmedUser -> Http.Request Token
login (Trimmed user) =
    let
        body =
            Http.jsonBody (User.toJson user)
    in
        Api.login body


getMe : Token -> Http.Request User.Model
getMe token =
    Api.me token


-- EXPORT


toSession : Model -> Session
toSession model =
    model.session