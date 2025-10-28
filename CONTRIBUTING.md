# Contributor guidelines

## Vision

The vision behind Gainz is the following:

- Gainz is an unopinionated framework for clients to build upon. Features should be customizable by the user from inside the client.

- Gainz is developed with a selfhosted, cut out from the internet environment in mind. This means no dependency on external services that may go down at any time without any fault of the user. It also means the server must handle authentication and authorization in a similarly selfhostable manner.

- No information withheld from the user. The client must be able to access everything the database has for a given user.

- Performance is a priority. Due to the simplistic nature outlined by the first bullet point, the biggest bottleneck should be the database and the hardware.

- No vendor lock-in. The users of Gainz must remain in control of their data at all times. Clients should respect this. The process to transfer your data from Gainz should be effortless for the user, even at the cost of performance. The process to transfer data from another platform to Gainz should also be as effortless as the other platform permits.

- As much work is offloaded to the client as you reasonably can, without sacrificing performance. The exceptions for this are: querying the database in an efficient way vs filtering on the client.

## Feature requests

If you have any feature requests that fit the vision of the future of Gainz, open an issue with the label `Feature Request`.

## Bugs

If you encounter any bugs and issues, open an issue with the label `Bug`. Include a reproducable example if possible.

## Pull requests

If the pull request introduces a new feature, please make sure to first file a `Feature Request` issue before beginning work on the pull request, as it is possible the feature does not get accepted and your time is wasted.

If the pull request is a bug-fix, there is no need for an issue.

Please follow the style guide when sending pull requests.

## Style guide

- Use `zig fmt`.

- File and library `@import`s should be at the bottom of the file. [You can check out the following discussion on why imports at the bottom are neat.](https://ziggit.dev/t/rationale-behind-import-at-the-end-of-file/9116)

- Function names are camelCase. Variables are snake_case. Types are PascalCase.

- Code should document itself, but for public functions/variables/types/etc, include a [doc comment](https://ziglang.org/documentation/master/#Doc-Comments) when necessary (such as for when the function returns something that needs to be freed).
