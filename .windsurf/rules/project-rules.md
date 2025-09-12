---
trigger: always_on
---

# General Rules
- All necessary services can be started using `bun run dev` from the root directory. This runs the `turbo dev` script defined in package.json. This, in turn, runs the Docker Compose file defined in docker-compose.yml, which starts the CoTURN server for NAT traversal and a local instance of the hosted signaling server.
- When adding new packages, consider the root turbo.json file for build and run steps. If a new package requires a build step, add it to the root turbo.json file.
- When adding new services to docker-compose.yml, consider the root docker-compose.yml file for service configuration.
- Prefer incremental changes to client-side code.
- This project's client-side code involves creating peer-to-peer connections between many clients. Testing requires spawning many simulators on the same machine, and booting/installing the app on all simulators is extremely time-intensive. Prefer incremental changes to client side code, except when batch changes requiring complete rebuilds/restarts (installing new packages, changing Info.plist permissions, Rust code changes, etc.) would be more efficient; think ahead about what future changes are necessary and will require restarts and walk me through your plan and confirm the changes with me that hot module replacement alone will not be able to handle. (Example: the app will need a crypto shim, a UUID library to uniquely identify peers to the signaling server and to each other, and a WebRTC adapter library, and an on-device storage library; the app will need updated permissions to store on-device data, and updated Info.plist permissions to allow the app to open links from other apps; list and explain these changes to the developer, and ask for confirmation before making them)
- I am a newbie when it comes to WebRTC and concepts like NAT Traversal, STUN/TURN servers, and ICE candidates. I am also a newbie when it comes to Rust and Tauri. Confirm that I understand what needs to be built and/or fixed before starting to write new code or making changes to existing code that would affect these areas.
- For the WebRTC and P2P code, the goal is to make ANY CLIENT a signaling device. This means that any client can act as a signaling server for known peers, and any client can act as a signaling client for another client. This fact implies that any signaling, WebRTC, and P2P code should be able to run agnostic of any environment where possible, and utilizing façade patterns to abstract environment-specific code behind interfaces that can be used by any environment.
- Prefer to utilize turborepo to avoid unnecessary rebuilds and consolidate build and run steps; new packages created should consider the root turbo.json file for build and run step
- When solutions require Rust, please walk me through the code line-by-line and explain the logic of the code
- When solutions require WebRTC, please walk me through the code line-by-line and explain the logic of the code
- All server side JavaScript code is to be written in TypeScript with Bun APIs, not Node.js APIs
- All client side JavaScript code is to be written in TypeScript with Svelte 5 and SvelteKit. If you are unsure about how to implement something, look at Svelte 5's documentation. Do not write solutions in Svelte 4, or any other previous versions of Svelte.
- All test code that would be written in JavaScript should be instead written in TypeScript
- All package manager code and scripts are to use Bun; do not use npm, yarn, or pnpm
- My client-side testing setup is based on Vitest and Svelte Testing Library

# General Code Style & Formatting
- Use English for all code and documentation.
- Always declare the type of each variable and function (parameters and return value).
- Avoid using any.
- Create necessary types.
- Use JSDoc to document public classes and methods.
- Use empty lines to break up code into logical parts.
- Organize imports in order of line length from shortest line length to longest; group imports by type (e.g. built-in, external, internal) and sort each group by maximum line length, shortest to longest


# Naming Conventions
- Use PascalCase for classes.
- Use camelCase for variables, functions, and methods.
- Use kebab-case for file and directory names.
- Use UPPERCASE for environment variables
- Use UPPER_SNAKE_CASE for constants
- Avoid magic numbers and define constants.

# Functions & Logic
- Keep functions short and single-purpose (<20 lines).
- Avoid deeply nested blocks by:
- Using early returns.
- Extracting logic into utility functions.
- Use higher-order functions (map, filter, reduce) to simplify logic.
- Use arrow functions for simple cases (<3 instructions), named functions otherwise.
- Use default parameter values instead of null/undefined checks.
- Use RO-RO (Receive Object, Return Object) for passing and returning multiple parameters.
- For functions that accept multiple arguments, expect typed object literals so that all variables are labeled and explicitly typed

# Data Handling
- Avoid excessive use of primitive types; encapsulate data in composite types.
- Avoid placing validation inside functions—use classes with internal validation instead.
- Prefer immutability for data:
- Use readonly for immutable properties.
- Use as const for literals that never change.