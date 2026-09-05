## Placeholder module for the `roc-time` package.
##
## The real date and time API will replace this; for now it exists so the
## package, examples, docs, and CI scaffolding all have something to build.
Time :: {}.{

	## A greeting, used to check the package is wired up correctly.
	##
	## ```roc
	## expect Time.hello("World") == "Hello, World!"
	## ```
	hello : Str -> Str
	hello = |name| "Hello, ${name}!"

	## The greeting includes the given name.
	expect hello("World") == "Hello, World!"
}
