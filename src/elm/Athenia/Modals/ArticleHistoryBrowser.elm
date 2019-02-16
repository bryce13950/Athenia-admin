module Athenia.Modals.ArticleHistoryBrowser exposing (..)

import Athenia.Api as Api exposing (Token)
import Athenia.Components.LoadingIndicator as LoadingIndicator
import Athenia.Models.Wiki.Iteration as Iteration
import Athenia.Session as Session exposing (..)
import Bootstrap.Modal as Modal
import Html exposing (..)
import Http


type alias Model =
    { articleId : Int
    , session : Session
    , token : Token
    , visibility : Modal.Visibility
    , showLoading : Bool
    , iterations : List Iteration.Model
    }


init : Int -> Session -> Token -> Model
init articleId session token =
    { articleId = articleId
    , session = session
    , token = token
    , visibility = Modal.hidden
    , showLoading = False
    , iterations = []
    }


initLoad : Model -> (Model, Cmd Msg)
initLoad model =
    ( { model
        | showLoading = True
        , visibility = Modal.shown
        , iterations = []
    }
    , loadIterations model.token model.articleId 1
    )


-- Create the view for the article creation modal
view : Model -> Html Msg
view model =
    div []
        [ Modal.config Cancel
            |> Modal.large
            |> Modal.h4 [] [ text "Article History" ]
            |> Modal.body []
                [
                ]
            |> Modal.view model.visibility
        , LoadingIndicator.view model.showLoading
        ]

type Msg
    = Cancel
    | CompletedArticleIterationLoad (Result Http.Error Iteration.Page)


hide : Model -> Model
hide model =
    { model
        | visibility = Modal.hidden
    }

-- HTTP


loadIterations : Token -> Int -> Int -> Cmd Msg
loadIterations token articleId page =
    Http.send CompletedArticleIterationLoad
        <| Api.viewArticleIterations token articleId page