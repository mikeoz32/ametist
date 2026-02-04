# ametist

TODO: Write a description here

## Installation

TODO: Write installation instructions here

## Usage

TODO: Write usage instructions here

## Movie Extensions

Movie supports Akka-style extensions via `ExtensionId`. Extensions are lazily created per actor system.

```crystal
remote = Movie::Remote::Remoting.get(system)
exec   = Movie::Execution.get(system)

# inside actors
exec = ctx.extension(Movie::Execution)
```

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/your-github-user/ametist/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

## Agency System
A new agentic runtime enables LLM‑driven workflows with pluggable models, tool bridges, and persistent state. See the detailed design in `docs/plans/2026-01-28-agency-design.md`.

- [Mike Oz](https://github.com/your-github-user) - creator and maintainer
