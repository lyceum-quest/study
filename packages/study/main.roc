## Study logic shared by the Elm app's port to roc-signals, in pure Roc: review
## scheduling and queues (`Review`, from src/Review.elm), finished attempts
## (`Study`, from src/Study.elm), and a work's passages from the preload
## (`Corpus`, from src/Conllu.elm and src/Passage.elm). Records encode and
## decode in the shapes the Elm app keeps in IndexedDB.
package
	[
		Corpus,
		Library,
		Review,
		Route,
		Study,
	]
	{
		fsrs: "../fsrs/main.roc",
		json: "../json/main.roc",
	}
