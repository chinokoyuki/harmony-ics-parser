# Contributing

Bug reports and pull requests are welcome.

## Reporting a problem

Include the smallest `.ics` snippet that reproduces the issue, plus the expected output. Trim anything personal from the file: names, email addresses, locations.

## Pull requests

- Keep the module free of runtime dependencies.
- ArkTS strict mode applies. Avoid `any`, `unknown` and type assertions.
- Parse and expand separately. Anything that touches the file system, UI or network belongs in the consuming app.
- Add a test in `src/test` for new behaviour. Tests use `@ohos/hypium`.
- Update `CHANGELOG.md` under an "Unreleased" heading.

## Style

Two-space indentation, single quotes, explicit types on exported functions. Comments explain decisions, not syntax.

## License

Contributions are accepted under the Apache-2.0 license used by this project.
