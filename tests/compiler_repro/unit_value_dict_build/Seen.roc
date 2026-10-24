## A dictionary used as a set: every key maps to the empty record.
Seen :: [].{
	contains_inserted : U64 -> Bool
	contains_inserted = |id| Dict.contains(Dict.insert(Dict.empty(), id, {}), id)
}
