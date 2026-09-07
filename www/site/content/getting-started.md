# Run your first application

Start with a released application and its compiler pin. Keep the complete example folder: its `main.roc` handles inputs and output, while companion modules contain the useful domain logic.

## 1. Get the starter kit

Download [roc-time-starter.zip for 0.1.0-rc3](https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc3/roc-time-starter.zip) and extract it. The kit includes booking exchange, archive search and staffing applications.

Install the Roc compiler named by its application headers: [nightly-2026-09-05-b195f5b](https://github.com/roc-lang/nightlies/releases/tag/nightly-2026-09-05-b195f5b). Roc has no versioned stable release yet; this is the compiler selected for this package release.

## 2. Run the booking example

From the extracted starter-kit folder:

```sh
roc version
roc examples/booking_exchange/main.roc
```

The version command should identify `nightly-2026-09-05-b195f5b`. The application prints available UTC windows after subtracting two bookings, including one supplied with a different offset. It also saves and restores the result.

**No Python runner is required to run an example.** On first use Roc downloads the content-addressed package dependencies declared in the header.

## 3. Change an input

Open `examples/booking_exchange/main.roc`. Change one booking while keeping an explicit `Z` or numeric offset. Run the same command again. The companion `BookingExchange.roc` performs parsing, coverage subtraction and persistence through public library APIs.

Keep both files together. The root file’s `import BookingExchange` resolves its neighboring module; copying only `main.roc` loses the application’s implementation.

## Use the library in your own app

Keep the platform declaration appropriate to your application, and copy the `roc` and `time` fields from `examples/booking_exchange/main.roc` in the downloaded rc3 starter kit. The release’s core package URL is:

```text
https://github.com/lukewilliamboswell/roc-time/releases/download/0.1.0-rc3/roc-time-9gC9GQxjZjAaAPGwaGwSYCGfTuN5ED4AstyM9vdCPe5o.tar.zst
```

Applications using named zones also add the `zones` dependency shown in `examples/staffing/main.roc` in the same starter kit. The core package does not bring the zone database with it.

## Choose your next step

- [Find availability](booking.html): exact timestamps, spans and coverage.
- [Calculate dates and handle clock changes](calendar-zones.html): calendar arithmetic and local interpretation.
- [Generate schedules](schedules.html): bounded recurrence and source identity.

If an API you saw in a development example is missing, check [versions](versions.html) before changing imports or compiler versions.
