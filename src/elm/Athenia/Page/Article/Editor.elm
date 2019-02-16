module Athenia.Page.Article.Editor exposing (Model, Msg, init, subscriptions, toSession, update, view)

import Athenia.Api as Api exposing (Token)
import Athenia.Components.LoadingIndicator as LoadingIndicator
import Athenia.Modals.ArticleHistoryBrowser as ArticleHistoryBrowser
import Athenia.Models.Wiki.Article as Article
import Athenia.Models.Wiki.Iteration as Iteration
import Athenia.Ports.ArticleSocket as ArticleSocket
import Athenia.Route as Route
import Athenia.Session as Session exposing (Session)
import Athenia.Viewer as Viewer
import Bootstrap.Button as Button
import Bootstrap.Form as Form
import Bootstrap.Form.Textarea as Textarea
import Bootstrap.Grid as Grid
import Bootstrap.Grid.Col as Col
import Html exposing (..)
import Html.Attributes exposing (class, id)
import Html.Events exposing (onClick)
import Http
import Time



-- MODEL


type alias Model =
    { session : Session
    , showLoading : Bool
    , token : Token
    , article : Status
    , articleHistoryBrowser : ArticleHistoryBrowser.Model
    }


type
    Status
    = Loading Int
    | LoadingFailed
    | Editing Article.Model (List Problem) Form


type Problem
    = ServerError String


type alias Form =
    { content : String
    , lastContentSnapshot : String
    }


init : Session -> Token -> Int -> ( Model, Cmd Msg )
init session token articleId =
    ( { session = session
      , showLoading = True
      , token = token
      , article = Loading articleId
      , articleHistoryBrowser
            = ArticleHistoryBrowser.init articleId session token
      }
    , Cmd.batch
        [ fetchArticle token articleId
        , ArticleSocket.connectArticleSocket ((Api.unwrapToken token), articleId)
        ]
    )


-- VIEW


view : Model -> { title : String, content : Html Msg }
view model =
    { title =
        case model.article of
            Editing article _ _ ->
                "Edit Article - " ++ article.title

            _ ->
                "Loading"

    , content =
        viewContent model
    }


viewContent : Model -> Html Msg
viewContent model =
    let
        formHtml =
            case model.article of
                Loading _ ->
                    []

                Editing article problems form ->
                    [ viewTitle article
                    , viewHistoryButtons
                    , viewProblems problems
                    , viewForm model.token form
                    ]

                LoadingFailed ->
                    [ text "Article failed to load." ]
    in
    div [ id "article-editor", class "page" ]
        [ Grid.container []
            [ Grid.row []
                [ Grid.col [Col.md12]
                    formHtml
                ]
            ]
        , LoadingIndicator.view model.showLoading
        , ArticleHistoryBrowser.view model.articleHistoryBrowser
            |> Html.map ArticleHistoryBrowserMsg
        ]


viewTitle : Article.Model -> Html msg
viewTitle article =
    h1 [ id "title" ] [ text article.title ]


viewHistoryButtons : Html Msg
viewHistoryButtons =
    Button.button
        [ Button.attrs [onClick ViewHistory]
        , Button.info
        ] [ text "View Article History" ]


viewProblems : List Problem -> Html msg
viewProblems problems =
    ul [ class "error-messages" ]
        (List.map viewProblem problems)


viewProblem : Problem -> Html msg
viewProblem problem =
    let
        errorMessage =
            case problem of
                ServerError message ->
                    message
    in
    li [] [ text errorMessage ]


viewForm : Token -> Form -> Html Msg
viewForm token fields =
    Form.form [ ]
        [ h2 [] [ text "Enter the article contents below." ]
        , Textarea.textarea
            [ Textarea.rows 20
            , Textarea.onInput EnteredContent
            , Textarea.value fields.content
            ]
        ]


-- UPDATE


type Msg
    = ViewHistory
    | EnteredContent String
    | CompletedLoadArticle (Result Http.Error Article.Model)
    | GotSession Session
    | ReceivedUpdatedContent String
    | ReportContentChanges Time.Posix
    | ArticleHistoryBrowserMsg ArticleHistoryBrowser.Msg


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ViewHistory ->
            let
                articleHistoryBrowserUpdate
                    = ArticleHistoryBrowser.initLoad model.articleHistoryBrowser
            in
            ( { model
                | articleHistoryBrowser =
                    Tuple.first articleHistoryBrowserUpdate
            }
            , Cmd.map ArticleHistoryBrowserMsg
                <| Tuple.second articleHistoryBrowserUpdate
            )


        ArticleHistoryBrowserMsg subMsg ->
            let
                articleHistoryBrowserUpdate
                    = ArticleHistoryBrowser.update subMsg model.articleHistoryBrowser
            in
            ( { model
                | articleHistoryBrowser =
                    Tuple.first articleHistoryBrowserUpdate
            }
            , Cmd.map ArticleHistoryBrowserMsg
                <| Tuple.second articleHistoryBrowserUpdate
            )

        EnteredContent content ->
            updateForm (\form -> { form | content = content }) model

        CompletedLoadArticle (Err err) ->
            ( { model | showLoading = False, article = LoadingFailed }
            , Cmd.none
            )

        CompletedLoadArticle (Ok article) ->
            let
                form =
                    { content = article.content
                    , lastContentSnapshot = article.content
                    }
            in
            ( { model
                | showLoading = False
                , article = Editing article [] form
            }
            , Cmd.none
            )

        GotSession session ->
            case Viewer.maybeToken (Session.viewer session) of
                Just token ->
                    ( { model
                        | session = session
                        , token = token
                    }
                    , Cmd.none
                    )
                Nothing ->
                    ( model
                    , Route.replaceUrl (Session.navKey session) Route.Login
                    )

        ReceivedUpdatedContent updatedContent ->
            updateForm
                (\form ->
                    { form
                        | lastContentSnapshot = updatedContent
                        , content = mergeContent form.lastContentSnapshot form.content updatedContent
                    }
                ) model

        ReportContentChanges _ ->
            case model.article of
                Editing articleModel errors form ->
                    if form.content == form.lastContentSnapshot then
                        (model, Cmd.none)
                    else
                        let
                            action =
                                Iteration.getContentActionType form.lastContentSnapshot form.content
                            updatedForm =
                                { form
                                    | lastContentSnapshot = form.content
                                }
                        in
                        ( { model
                            | article = Editing articleModel errors updatedForm
                        }
                        , if action == Iteration.NoAction then
                            Cmd.none
                        else
                            ArticleSocket.sendUpdateMessage
                                <| (Iteration.encodeAction action, articleModel.id)
                        )

                _ ->
                    (model, Cmd.none)



{-| Helper function for `update`. Updates the form, if there is one,
and returns Cmd.none.

Useful for recording form fields!

This could also log errors to the server if we are trying to record things in
the form and we don't actually have a form.

-}
updateForm : (Form -> Form) -> Model -> ( Model, Cmd Msg )
updateForm transform model =
    let
        newModel =
            case model.article of
                Editing article errors form ->
                    { model | article = Editing article errors (transform form) }

                _ ->
                    model

    in
    ( newModel, Cmd.none )


mergeContent : String -> String -> String -> String
mergeContent lastContentSnapShot localContent remoteContent =
    if lastContentSnapShot == localContent then
        -- content has not changed locally, we can just return the remote content
        remoteContent
    else
        let
            remoteAction =
                Iteration.getContentActionType lastContentSnapShot remoteContent
            localAction =
                Iteration.getContentActionType lastContentSnapShot localContent

        in
        case (Iteration.getActionStartPosition remoteAction, Iteration.getActionStartPosition localAction) of
            (Just remoteStartPosition, Just localStartPosition) ->
                if remoteStartPosition >= localStartPosition then
                    Iteration.applyAction localAction
                        <| Iteration.applyAction remoteAction lastContentSnapShot
                else
                    Iteration.applyAction remoteAction
                        <| Iteration.applyAction localAction lastContentSnapShot

            (Just _, Nothing) ->
                remoteContent

            (Nothing, Just _) ->
                localContent

            _ ->
                lastContentSnapShot

-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Session.changes GotSession (Session.navKey model.session)
        , ArticleSocket.articleUpdated ReceivedUpdatedContent
        , Time.every 500 ReportContentChanges
        ]


-- HTTP


fetchArticle : Token -> Int -> Cmd Msg
fetchArticle token articleId =
    Http.send CompletedLoadArticle
        <| Api.getArticle token articleId


-- EXPORT


toSession : Model -> Session
toSession model =
    model.session
