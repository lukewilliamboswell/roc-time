import time.Coverage
import time.ExactInterval

## Consume ordered booking input in bounded stages, retaining the next span on pause.
BookingStream :: [].{
	consume! = |initial, limit| {
		var $progress = initial
		while True {
			match $progress.pending {
				Pending(span) => {
					match $progress.builder.append_bounded({ span, max_members: limit })? {
						Added(builder) => {
							$progress = { ..$progress, builder, pending: Ready }
						}
						Full(builder) => return Ok(Paused({ ..$progress, builder }))
					}
				}
				Ready => match $progress.source.next!() {
					Done => return Ok(Completed($progress.builder.to_coverage()))
					Skip({ rest }) => {
						$progress = { ..$progress, source: rest }
					}
					One({ item, rest }) => {
						text = item?
						booking = ExactInterval.parse(text)?
						$progress = { ..$progress, source: rest, pending: Pending(booking.span()) }
					}
				}
			}
		}
	}
}
