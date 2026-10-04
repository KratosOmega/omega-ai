# CLI fixtures (synthetic)

These files are synthetic. They are hand-built to match the key sets, envelopes,
value forms (Z timestamps, `properties` keyed by property id) and error texts and
exit codes of the 2026-10-04 P7 recording of the multica CLI 0.6.x. All ids,
identifiers and names are invented ("Operator", operator@example.com, "gd-probe",
host.example.lan). No workspace data is committed.

`test_cli.py::test_stub_conformance` pins `stub-multica` against them: each
fixture maps to one stub command, and the key sets must match exactly.
`errors/<name>.txt` and `.exit` are the stderr text and exit code of the recording. `duplicate` and
`bad-status` are templates: `{ident}`, `{title}` and `{status}` are filled in by the stub. There
is no `errors/forbidden.txt`; the stub uses its default text.
