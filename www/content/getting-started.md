# Run your first application

Start with a released application and its compiler pin. Keep the complete example folder: its `main.roc` handles inputs and output, while companion modules contain the useful domain logic.

## 1. Get the starter kit

Choose a [package release](https://github.com/lukewilliamboswell/roc-time/releases), download its starter ZIP and extract it. The release notes identify the packages, compiler and included applications.

Install the compiler declared in the example's `roc` header. Keep the package URLs from the same kit.

## 2. Run the booking example

From the extracted starter-kit folder:

```sh
roc version
roc examples/booking_exchange/main.roc
```

Check that the version command matches the application header. The application prints available UTC windows after subtracting two bookings, including one supplied with a different offset.

**No Python runner is required to run an example.** On first use Roc downloads the content-addressed package dependencies declared in the header.

## 3. Change an input

Open `examples/booking_exchange/main.roc`. Change one booking while keeping an explicit `Z` or numeric offset. Run the same command again. The companion `BookingExchange.roc` performs parsing and coverage subtraction through public library APIs.

Keep both files together. The root file’s `import BookingExchange` resolves its neighboring module; copying only `main.roc` loses the application’s implementation.

## Use the library in your own app

Keep the platform declaration appropriate to your application, and copy the `roc` and `time` fields from the downloaded example. These headers are the source of truth for the compatible compiler and immutable package URL.

Applications using named zones also add the `zones` dependency shown in `examples/staffing/main.roc` in the same starter kit. The core package does not bring the zone database with it.

## Choose your next step

- [Find availability](booking.html): exact timestamps, spans and coverage.
- [Calculate dates and handle clock changes](calendar-zones.html): calendar arithmetic and local interpretation.
- [Generate schedules](schedules.html): bounded recurrence and source identity.

If an API you saw in a development example is missing, check [versions](versions.html) before changing imports or compiler versions.
