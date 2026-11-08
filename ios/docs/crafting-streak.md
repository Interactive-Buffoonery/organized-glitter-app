# Crafting streak

Account offers **Crafting streak**, with the description **Lets you track your
consecutive crafting days!** Choose Off (default), Show on Home, or Show in Notes.
Home opens Notes; the Notes header indicator is a noninteractive status.
A known zero uses the theme-accent outline flame without a number. Positive
counts use the filled accent flame and count. Unavailable data uses a neutral
ellipsis and never implies zero.

The mode is local to this installation and signed-in user, stored under
`crafting-streak-mode.<userID>`. On first use, the retained legacy
`show-crafting-streak.<userID>` boolean migrates true to home and false/missing
to off. Any existing new value wins; invalid values display off. The legacy
key remains untouched for older app versions. No backend preference changes.

The indicator reads only the active LibrarySession's complete downloaded
snapshot. Both crafts count before feed filters, using the existing NotesFeed
parent eligibility. Failed initial or rejected snapshots are unavailable;
a complete downloaded snapshot remains usable while stale or offline, with the
existing library sync context also exposed in the indicator's accessibility value.
Account close makes the indicator unavailable.

PocketBase date fields carry a time suffix. As in the existing native date-only
contract, extract their leading saved day without interpreting them as instants.
Distinct valid Gregorian `yyyy-MM-dd` date labels then count consecutively
through today or yesterday in the account timezone. Future dates cannot extend
the streak. Gregorian day arithmetic uses date labels rather than elapsed hours.
The indicator updates every minute and resumes with the current day. Account
refreshes and timezone setting changes supply the latest account timezone.

New notes default to the account's current day. The editor retains a date string,
materializes it in the picker's timezone for display, and extracts the components
in that same timezone after a choice. Submission materializes those saved
components in the transport's device timezone, matching its existing date-only
serialization. Inline note editing also retains a date string and rematerializes the picker
components in its current timezone. Saved and picked labels survive device
timezone changes without moving to the account timezone.

Shared synthetic count cases are in
`OrganizedGlitterTests/Fixtures/crafting-streak-cases.json`. Each case supplies
an ISO UTC instant, IANA timezone, saved note date strings, and expected count.
Native tests load the JSON directly; the web implementation can consume the
same cases. They cover duplicates, gaps, invalid dates, future dates, leap days,
DST boundaries, timezone midnight, and year rollover.
