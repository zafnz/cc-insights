# Feature Documentation

This directory contains detailed documentation for specific features of CC Insights.

## Purpose

Feature docs are different from architectural documentation or SDK references:

- **Feature docs** describe *what* the feature does, *how* users interact with it, and *why* design decisions were made
- **Architectural docs** (`/CLAUDE.md`) describe the overall system design and implementation patterns
- **SDK docs** (`/docs/sdk/`) describe the Claude Agent SDK API reference

## Feature Documents

### Configuration System

**[config-cli-files.md](config-cli-files.md)** - Configuration system design

Describes the layered configuration approach using:
- Config files (`~/.cc-insights/config.yaml`)
- Environment variables (`CC_*` prefix)
- CLI arguments (highest precedence)

Includes precedence rules, security considerations, and implementation guidance.

## Document Structure

Each feature document should include:

1. **Overview** - What the feature does and why it exists
2. **User Experience** - How users interact with the feature
3. **Configuration/API** - How to use or configure the feature
4. **Implementation Notes** - Technical details for developers
5. **Examples** - Practical usage examples
6. **Security/Edge Cases** - Important considerations
7. **Testing** - How to test the feature
8. **Related Issues** - Links to GitHub issues

## When to Create a Feature Doc

Create a feature doc when:

- The feature has multiple configuration options or modes
- The feature involves user interaction workflows
- The feature has security implications
- The feature requires examples to understand
- The feature is complex enough to warrant dedicated documentation

## When NOT to Create a Feature Doc

Don't create a feature doc for:

- Simple bug fixes (document in commit message or PR)
- Minor UI tweaks
- Internal refactoring (document in code or architectural docs)
- Temporary workarounds

## Relationship to Other Docs

```
/CLAUDE.md                    # Overall architecture and dev guide
├── /docs/features/           # User-facing feature documentation
│   ├── config-cli-files.md   # Configuration system
│   └── ...                   # Other features
├── /docs/sdk/                # Claude Agent SDK reference
├── /docs/dart-sdk/           # Dart SDK implementation details
├── /docs/LOGGING.md          # Logging system documentation
└── /docs/archive/            # Historical/outdated documentation
```

## Contributing

When implementing a new feature:

1. Create a feature doc *before* or *during* implementation
2. Update the doc as design decisions change
3. Link to the doc from GitHub issues
4. Reference the doc in PR descriptions
5. Keep the doc updated as the feature evolves
