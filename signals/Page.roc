import pf.Engine exposing [Elem, Handler, In, Root, State, Signal]
import pf.Html
import Model
import Update

## What every view shares: the app's state context, handlers that run a
## transition through Update (as every Elm message goes through `update`),
## and small markup helpers.
Page := [].{

	S : In(Root, Model.Model)

	## A handler running `change` on the app.
	act : State(S, Model.Model), (Model.Model -> Model.Model) -> Handler(S)
	act = |session, change| session.update(|model| Update.step(model, change))

	## A handler running `change` with the event's value (an input's text, a select's choice).
	act_value : State(S, Model.Model), (Model.Model, Str -> Model.Model) -> Handler(S)
	act_value = |session, change| session.set_value(|model, value| Update.step(model, |m| change(m, value)))

	## A `type="button"` button.
	button : Str, Str, Handler(ctx) -> Elem(ctx)
	button = |label, class, handler| Html.button(label, [Engine.class(class), Engine.attr("type", "button")], handler)

	strong : Str -> Elem(ctx)
	strong = |text| Engine.element("strong", [], [Engine.text(text)])

	## A link to another site, in a new tab so the session stays open.
	external : Signal(ctx, Str), Signal(ctx, Str), Signal(ctx, Str) -> Elem(ctx)
	external = |url, description, label|
		Engine.element("a", [Engine.attr_s("href", url), Engine.attr("target", "_blank"), Engine.attr("rel", "noopener"), Engine.attr_s("title", description)], [Engine.text_s(label)])
}
