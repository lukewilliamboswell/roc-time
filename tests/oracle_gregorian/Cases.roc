import GregorianOracle

## Small directly runnable smoke input. The oracle gate substitutes input batches.
Cases :: [].{
	inputs : List(GregorianOracle)
	inputs = [Forward(0, 1970, 1, 1), Inverse(1, 0)]
}
