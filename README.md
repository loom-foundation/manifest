# Loom workspace manifest

The [west](https://docs.zephyrproject.org/latest/develop/west/) manifest that assembles the Loom Foundation's repositories into one working tree. The projects are declared in [`west.yml`](west.yml).

## Setup

```
west init -l manifest
west update
```

`west init -l manifest` sets the workspace root to this repository's parent directory, so `.west/` and every project checkout live alongside it; `west update` then clones the projects listed in `west.yml`.
