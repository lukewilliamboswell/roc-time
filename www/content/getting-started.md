# Run your first application

Start with a released application. Keep the complete example folder: its `main.roc` handles inputs and output, while companion modules contain the useful domain logic.

## 1. Get the examples archive

Choose a [package release](https://github.com/lukewilliamboswell/roc-time/releases), download its `roc-time-examples-<version>.zip` and extract it. The release notes identify the packages, compiler and included applications.

Install the Roc compiler named in the release notes, or a later nightly. The applications do not pin a compiler. Keep the package URLs from the same archive.

## 2. Run the booking example

From the extracted folder:

```sh
roc version
roc examples/booking_exchange/main.roc
```

Compare the version command with the release notes. The application prints available UTC windows after subtracting two bookings, including one supplied with a different offset.

**No Python runner is required to run an example.** On first use Roc downloads the content-addressed package dependencies declared in the header.

## 3. Change an input

Open `examples/booking_exchange/main.roc`. Change one booking while keeping an explicit `Z` or numeric offset. Run the same command again. The companion `BookingExchange.roc` performs parsing and coverage subtraction through public library APIs.

Keep both files together. The root file’s `import BookingExchange` resolves its neighboring module; copying only `main.roc` loses the application’s implementation.

## Use the library in your own app

Keep the platform declaration appropriate to your application, and copy the `time` field from the downloaded example. That header is the source of truth for the immutable package URL; the release notes record the compiler the release was built and tested with.

Applications using named zones also add the `zones` dependency shown in `examples/staffing/main.roc` in the same archive. The core package does not bring the zone database with it.

## Choose your next step

- [Find availability](booking.html): exact timestamps, spans and coverage.
- [Calculate dates and handle clock changes](calendar-zones.html): calendar arithmetic and local interpretation.
- [Generate schedules](schedules.html): bounded recurrence and source identity.

If an API you saw in a development example is missing, check [versions](versions.html) before changing imports or compiler versions.
