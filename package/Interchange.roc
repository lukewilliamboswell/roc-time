import Ixdtf as IxdtfType
import EdtfInterval as EdtfIntervalType
import EdtfDate as EdtfDateType

## Read and write EDTF descriptions and annotated IXDTF timestamps.
Interchange :: [].{

	## IxdtfSnapshot for bounded evaluation or retained state.
	IxdtfSnapshot : IxdtfType.Snapshot

	## Ixdtf operations and types.
	Ixdtf : IxdtfType

	## EdtfInterval operations and types.
	EdtfInterval : EdtfIntervalType

	## EdtfDate operations and types.
	EdtfDate : EdtfDateType

}
