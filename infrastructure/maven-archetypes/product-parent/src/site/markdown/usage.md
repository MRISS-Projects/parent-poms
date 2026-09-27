# Usage

## Before Start

Check the instructions about the local catalog at [this link](../before-running.html).

## Subversion

### With catalog:

```bash
mvn -Dgoals=validate archetype:generate
```

When asked select option **3**:

### With specific version at command line

Usually useful for testing new version locally:

```bash
mvn -DarchetypeCatalog=local -DarchetypeArtifactId=product-parent -DarchetypeGroupId=com.mriss.mriss-parent.infrastructure.maven-archetypes -DarchetypeVersion=2.0.0-SNAPSHOT -Dgoals=validate archetype:generate
```

## Git

### Setup

1. Git should be installed and git executable should be in the path. In windows based systems the path should usually contains [GIT_HOME]\bin.

2. Set environment variable GIT to true.

    1. In linux:

        ```bash
        export GIT=true
        ```

    2. In windows:

        ```bat
        set GIT=true
        ```

### With catalog:

```bash
mvn -Dgoals=validate archetype:generate
```

When asked select option **5**:

### With specific version at command line

Usually useful for testing new version locally:

```bash
mvn -DarchetypeCatalog=local -DarchetypeArtifactId=product-parent -DarchetypeGroupId=com.mriss.mriss-parent.infrastructure.maven-archetypes -DarchetypeVersion=2.0.0-SNAPSHOT -Dgoals=validate archetype:generate
```
