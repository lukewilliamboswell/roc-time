## Policy for reducing precision to whole microseconds. NearestTiesEven
## selects the even microsecond at an exact tie.
MicrosecondRounding := [RejectSubmicrosecond, Floor, Ceiling, TowardZero, NearestTiesEven]
