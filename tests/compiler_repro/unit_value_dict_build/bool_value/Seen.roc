## The control: the same dictionary with a Bool value instead of the empty record.
Seen :: [].{
	contains_inserted : U64 -> Bool
	contains_inserted = |id| Dict.contains(Dict.insert(Dict.empty(), id, True), id)
}
