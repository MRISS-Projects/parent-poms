# Spec: retry transient registry errors during a release (`#98`)

| | |
|---|---|
| Issue | [`#98`](https://github.com/MRISS-Projects/parent-poms/issues/98): `release:perform` fails the whole release on a transient GitHub Packages 500, with no retry |
| Milestone | `3.11.0-SNAPSHOT` |
| Branch | `issue-98-retry-transient-registry-errors`, cut from `master` at `4af23c69` |
| Found in | DSH 0.3.1 hotfix, [run 36712998895](https://github.com/MRISS-Projects/dsh/actions/runs/36712998895); recovered by `MRISS-Projects/dsh#146` |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal.** During `project-release.yml` and `project-hotfix.yml`, a single upload that GitHub
Packages answers with a transient 5xx is retried, rather than failing the release halfway.

**Architecture.** One job-level `MAVEN_ARGS` environment variable in each of the two reusable
workflows widens the resolver's existing HTTP retry to cover 500, 502 and 504, and raises the retry
count. Maven's own `mvn` script adds `MAVEN_ARGS` to every invocation, ahead of the command's own
arguments, and the release plugin's forked build inherits the environment, so the setting reaches
the `deploy` that `release:perform` forks. A `build.yml` check keeps the line from being dropped. No POM change, no
new action.

## 1. What is true today

Verified against the jars the workflows run: Maven 3.9.16 (pinned by `Set up Maven 3.9.16`),
`maven-resolver-transport-http` 1.9.27, `maven-deploy-plugin` 3.1.4 and `maven-release-plugin`
3.1.1 (`pom.xml` `deploy.plugin.version` and `release.plugin.version`).

1. **The resolver already retries, but not on a 500.** `HttpTransporter` installs
   `ResolverServiceUnavailableRetryStrategy`, which retries when the response status is in
   `aether.connector.http.retryHandler.serviceUnavailable`. That set defaults to `429,503`. The
   500 that ended DSH 0.3.1 was not in it, so it was not retried.
2. **That retry applies to uploads.** The strategy checks the status code only, not the method,
   and `HttpTransporter$PutTaskEntity.isRepeatable()` returns `true`, so HttpClient can resend
   the body. It retries the one failed request, not the module.
3. **Its count and interval are configurable.** `aether.connector.http.retryHandler.count`
   (default 3), `.interval` (default 5000 ms) and `.intervalMax` (default 300000 ms). A
   `Retry-After` header, when the server sends one, takes precedence over the interval. The wait
   grows with each attempt: `interval × attempt`, so five retries wait 5 + 10 + 15 + 20 + 25 =
   75 s. The same `count` also goes to HttpClient's I/O retry handler, which under the default
   `retryHandler.name` is `StandardHttpRequestRetryHandler(count, false)`, so raising it also allows more retries after an I/O failure on a request that was not fully
   sent. That is harmless, and useful against the same kind of transient trouble.
4. **`maven-deploy-plugin` 3.1.4 still has `retryFailedDeploymentCount`, and it is the wrong
   tool.** It re-runs the deploy of the whole module, so files that already went up are PUT
   again. GitHub Packages answers a second upload of a release version's file with 409 Conflict,
   so that retry can fail on a file that had succeeded.
5. **A `-D` on the outer `mvn` does not reach the release fork.** The fork's command line comes
   from `<arguments>` (root `pom.xml`, overridden in `products/pom.xml`). The `mvn` the fork
   launches is the same Maven 3.9.16 script, though, and it reads `MAVEN_ARGS` from the
   inherited environment (`bin/mvn`, line 216: `${CLASSWORLDS_LAUNCHER} ${MAVEN_ARGS} "$@"`).
   `MAVEN_ARGS` comes before the command's own arguments (line 26: "passed to Maven before CLI
   arguments"), so a `-D` for the same key on a command overrides it.
6. **Neither workflow sets `MAVEN_ARGS` or `MAVEN_OPTS` today.** Each job has a job-level `env:`
   holding only `DEPLOY_TOKEN`: `release` in `project-release.yml`, `hotfix` in
   `project-hotfix.yml`.
7. **Consumers call both workflows at `@master`.** A change merged here takes effect on every
   consumer's next release, without a parent re-pin.

## 2. Design

### 2.1 The setting

Both jobs get the same variable, next to `DEPLOY_TOKEN`:

```yaml
    env:
      DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
      # #98: GitHub Packages answered one PUT of DSH 0.3.1's release:perform with a transient
      # 500, and the release stopped with its tag pushed and 12 of 13 modules published. The
      # resolver retries a failed request on its own, but by default only on 429 and 503. This
      # adds 500, 502 and 504, and allows five attempts. It is MAVEN_ARGS, not a -D on a
      # command: Maven's mvn script adds it to every invocation, ahead of the command's own
      # arguments, so a -D for the same key on one command still wins. release:perform's
      # forked deploy inherits the environment, which a -D on the outer mvn never reaches.
      MAVEN_ARGS: >-
        -Daether.connector.http.retryHandler.serviceUnavailable=429,500,502,503,504
        -Daether.connector.http.retryHandler.count=5
```

- **The status codes** are the transient ones: rate limited, internal error, bad gateway,
  unavailable, gateway timeout. A 4xx other than 429 is never retried. It is an answer, not an
  outage.
- **The count** goes from 3 to 5. The interval stays at its default. With the resolver's backoff
  that covers about a minute or two of registry trouble per request.
- **Only these two workflows.** `project-stage.yml`, `project-staging.yml` and `deploy.yml` also
  upload to GitHub Packages, but a failed snapshot or RC deploy is simply re-run. Only a release
  leaves a pushed tag and a moved branch behind. Extending the setting is a later decision.

### 2.2 Rejected alternatives

- **The release plugin's `<arguments>`, in the root and `products` POMs.** This reaches only the
  release fork, not the rest of the job. Consumers get it only after re-pinning the parent, and a
  consumer that overrides `<arguments>` silently loses it.
- **`retryFailedDeploymentCount`.** See §1.4.
- **`MAVEN_OPTS`.** It would also work, as JVM system properties. `MAVEN_ARGS` is narrower: the
  values become user properties on the command line, which is exactly what a `-D` is.

### 2.3 The guard

A new `build.yml` step fails the build if either workflow loses the setting. It sits next to
`Check the reusable workflows declare no service containers` and follows that check's shape. It
reads the value of the `MAVEN_ARGS` key itself: the key's own text plus the more-indented lines
that fold into it, joined with spaces. It requires exactly one such key per file, holding exactly
the two flags. So none of these pass: a flag left behind in a comment, a near miss like
`count=50`, a flag moved onto one `mvn` command, the flags under another key while `MAVEN_ARGS`
is emptied, or a second `MAVEN_ARGS`.

### 2.4 Known limit

If GitHub Packages stores a file and still answers 500, the retry gets 409 and the release fails,
as today. Nothing on the client can tell that case from a real failure, and a 409 must not be
retried. That case stays a manual recovery, like `MRISS-Projects/dsh#146`. This change is never
worse than the current behaviour.

## 3. Acceptance criteria

- **AC001.** A PUT that the registry answers with 500 is retried and the deploy succeeds. Without
  the setting, the same deploy fails. (Task 1, probe A.)
- **AC002.** `MAVEN_ARGS` reaches the release plugin's forked build. (Task 1, probe B.)
- **AC003.** Every other `mvn` command in the two jobs behaves as before. In particular, the
  `help:evaluate … -DforceStdout` captures still print only the version. (Task 1, probe C.)
- **AC004.** `project-release.yml` and `project-hotfix.yml` both set `MAVEN_ARGS` as in §2.1.
  (Task 3.)
- **AC005.** `build.yml` fails if either workflow loses the setting. (Task 2.)
- **AC006.** A consumer's dry-run rehearsal still runs end to end after the merge. (Task 4.)

## 4. Tasks

All local commands run under Maven 3.9.16 and JDK 17 from `~/apps`, in a scratch directory
outside any repository unless a step says otherwise:

```bash
export PATH="$HOME/apps/apache-maven-3.9.16/bin:$HOME/apps/jdk-17.0.20.1+1/bin:$PATH"
export JAVA_HOME="$HOME/apps/jdk-17.0.20.1+1"
RETRY='-Daether.connector.http.retryHandler.serviceUnavailable=429,500,502,503,504 -Daether.connector.http.retryHandler.count=5'
```

### Task 1: the three local probes (AC001–AC003)

Evidence before the change. Nothing in this task is committed except the record in step 9.

**Files:** scratch only: `FakeRegistry.java`, `probe-a/pom.xml`, `probe-b/pom.xml`.

- [x] **Step 1: write the fake registry.** It answers the first PUT of each `.pom` with 500 and
  every other PUT with 201, and logs each request.

  ```java
  import com.sun.net.httpserver.HttpServer;
  import java.net.InetSocketAddress;
  import java.util.Set;
  import java.util.concurrent.ConcurrentHashMap;

  public class FakeRegistry {
      public static void main(String[] args) throws Exception {
          Set<String> failedOnce = ConcurrentHashMap.newKeySet();
          HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 8099), 0);
          server.createContext("/", exchange -> {
              String method = exchange.getRequestMethod();
              String path = exchange.getRequestURI().getPath();
              exchange.getRequestBody().readAllBytes();
              int code;
              if (!"PUT".equals(method)) {
                  code = 404;
              } else if (path.endsWith(".pom") && failedOnce.add(path)) {
                  code = 500;
              } else {
                  code = 201;
              }
              System.out.println(method + " " + path + " -> " + code);
              exchange.sendResponseHeaders(code, -1);
              exchange.close();
          });
          server.start();
          System.out.println("FakeRegistry on 127.0.0.1:8099");
      }
  }
  ```

  Start it in the background: `java FakeRegistry.java > fake-registry.log 2>&1 &`.

- [x] **Step 2: write probe A.** It's a release-version POM-packaged project, so the only upload
  that can fail is the `.pom`, the same file that failed in DSH 0.3.1.

  ```xml
  <project xmlns="http://maven.apache.org/POM/4.0.0">
    <modelVersion>4.0.0</modelVersion>
    <groupId>probe</groupId>
    <artifactId>probe-a</artifactId>
    <version>1.0</version>
    <packaging>pom</packaging>
    <build>
      <plugins>
        <plugin>
          <artifactId>maven-deploy-plugin</artifactId>
          <version>3.1.4</version>
        </plugin>
      </plugins>
    </build>
  </project>
  ```

- [x] **Step 3: red.** Deploy without the setting:

  ```bash
  (cd probe-a && mvn -B deploy -DaltDeploymentRepository=fake::http://127.0.0.1:8099/repo) \
    > probe-a-red.log 2>&1; echo "exit=$?"
  ```

  Expected: non-zero exit; the log names `status code: 500`; `fake-registry.log` shows one
  `PUT /repo/probe/probe-a/1.0/probe-a-1.0.pom -> 500` and no second PUT of that path.

- [x] **Step 4: green.** Restart the fake registry so its memory is empty, then deploy with the
  setting:

  ```bash
  (cd probe-a && MAVEN_ARGS="$RETRY" mvn -B deploy \
    -DaltDeploymentRepository=fake::http://127.0.0.1:8099/repo) > probe-a-green.log 2>&1; echo "exit=$?"
  ```

  Expected: exit 0; `fake-registry.log` shows the `.pom` path twice, `-> 500` then `-> 201`.

- [x] **Step 5: write probe B.** It's a `SNAPSHOT` in a local git repository whose only check is
  an enforcer rule, bound to `validate`, that requires a property named `probe`. The release
  plugin runs `validate` as its preparation goal, so the rule runs only in the fork.

  ```xml
  <project xmlns="http://maven.apache.org/POM/4.0.0">
    <modelVersion>4.0.0</modelVersion>
    <groupId>probe</groupId>
    <artifactId>probe-b</artifactId>
    <version>1.0-SNAPSHOT</version>
    <packaging>pom</packaging>
    <scm>
      <developerConnection>scm:git:file://${project.basedir}</developerConnection>
    </scm>
    <build>
      <plugins>
        <plugin>
          <artifactId>maven-enforcer-plugin</artifactId>
          <version>3.5.0</version>
          <executions>
            <execution>
              <id>require-probe</id>
              <phase>validate</phase>
              <goals><goal>enforce</goal></goals>
              <configuration>
                <rules><requireProperty><property>probe</property></requireProperty></rules>
              </configuration>
            </execution>
          </executions>
        </plugin>
        <plugin>
          <artifactId>maven-release-plugin</artifactId>
          <version>3.1.1</version>
          <configuration>
            <preparationGoals>validate</preparationGoals>
          </configuration>
        </plugin>
      </plugins>
    </build>
  </project>
  ```

  Then `git init`, `git add pom.xml` and `git commit -m probe` inside `probe-b`, so
  `release:prepare` finds no local modifications.

- [x] **Step 6: red, then the control, then green.** Each run is `release:prepare -DdryRun=true`,
  and each is preceded by `mvn -B release:clean`:

  ```bash
  (cd probe-b && mvn -B release:clean && mvn -B release:prepare -DdryRun=true) \
    > probe-b-red.log 2>&1; echo "exit=$?"
  (cd probe-b && mvn -B release:clean && mvn -B release:prepare -DdryRun=true -Dprobe=x) \
    > probe-b-control.log 2>&1; echo "exit=$?"
  (cd probe-b && mvn -B release:clean && MAVEN_ARGS='-Dprobe=x' mvn -B release:prepare -DdryRun=true) \
    > probe-b-green.log 2>&1; echo "exit=$?"
  ```

  Expected: red fails on `requireProperty`; green passes. The control is §1.5's premise. It is
  expected to fail. If it passes, record that: the design still holds, because `MAVEN_ARGS` is
  on the outer command line too, but §1.5 and the comment in §2.1 must be corrected.

- [x] **Step 7: probe C.** In this parent-poms checkout, the version capture used by both
  workflows prints the same thing with and without the setting:

  ```bash
  a=$(mvn -q help:evaluate -Dexpression=project.version -DforceStdout -N)
  b=$(MAVEN_ARGS="$RETRY" mvn -q help:evaluate -Dexpression=project.version -DforceStdout -N)
  [ "$a" = "$b" ] && [ "$a" = "3.11.0-SNAPSHOT" ] && echo same || echo "DIFFERENT: '$a' vs '$b'"
  ```

  Expected: `same`.

- [x] **Step 8: stop the fake registry.** Kill the `java FakeRegistry.java` process by its PID,
  captured with `echo $!` right after the start in step 1 and again after the restart in step 4.

- [x] **Step 9: record the outcome.** Add §6, "Probe results", to this spec: each probe's exit
  code and the relevant `fake-registry.log` lines. Commit:

  ```bash
  git add specs/98-retry-transient-registry-errors.md
  git commit -m "docs(#98): record the local retry probes"
  ```

### Task 2: the guard, red first (AC005)

**Files:** modify `.github/workflows/build.yml`, inserting after the
`Check the reusable workflows declare no service containers` step.

- [x] **Step 1: add the step.**

  ```yaml
      # #98: a release's deploy must retry a transient 5xx from GitHub Packages. The retry
      # lives in one MAVEN_ARGS line per release workflow (see
      # specs/98-retry-transient-registry-errors.md §2.1), and nothing else would notice it was
      # gone until the next 500 split a release in half. The check reads the VALUE of the
      # MAVEN_ARGS key - its own text plus the more-indented lines that fold into it, joined
      # with spaces - and requires exactly one such key per file, holding exactly the flags.
      # Searching for the flags anywhere in the file would also accept them left in a
      # comment, as count=50, on one mvn command (which never reaches release:perform's fork),
      # or under another key while MAVEN_ARGS is emptied.
      - name: Check the release workflows retry transient registry errors
        run: |
          set -euo pipefail
          want='-Daether.connector.http.retryHandler.serviceUnavailable=429,500,502,503,504 -Daether.connector.http.retryHandler.count=5'
          status=0
          for f in .github/workflows/project-release.yml .github/workflows/project-hotfix.yml; do
            values=$(awk '
              function flush() { if (inv) print v; inv = 0 }
              inv {
                match($0, /^[[:space:]]*/)
                if (RLENGTH > ind && $0 ~ /[^[:space:]]/) {
                  l = substr($0, RLENGTH + 1); v = (v == "" ? l : v " " l); next
                }
                flush()
              }
              /^[[:space:]]+MAVEN_ARGS:/ {
                match($0, /^[[:space:]]*/); ind = RLENGTH
                v = $0; sub(/^[[:space:]]+MAVEN_ARGS:[[:space:]]*/, "", v)
                if (v == ">-") v = ""
                inv = 1
              }
              END { flush() }' "$f")
            if [ "$values" != "$want" ]; then
              found=${values//$'\n'/ | }
              echo "::error file=$f::$f must set MAVEN_ARGS exactly once, to: $want (see #98). Found: ${found:-no MAVEN_ARGS}"
              status=1
            fi
          done
          [ "$status" -eq 0 ] && echo "Both release workflows retry transient registry errors."
          exit "$status"
  ```

- [x] **Step 2: run it locally, red.** Extract the `run:` body to a scratch script and run it
  from the repository root. Expected: `::error` lines for both files, and exit 1.

  The guard above is its third version. Each change started from a failing case: scratch copies
  of the two workflows that the guard of the day passed.

  - **The local review, before the PR**, replaced the first version's substring match with
    whole-line matches. The substring guard passed three copies: the flags only in a comment,
    `count=50`, and the flags on a single `mvn` command line instead of `MAVEN_ARGS`.
  - **Copilot's round 1 on PR #108** (Balanced effort, at `62f460df`) found that the whole-line
    guard searched for the key and the flags separately. It passed a copy with
    `MAVEN_ARGS: ""` and the flags under an `UNUSED_ARGS: >-` key. The guard now reads the
    value of `MAVEN_ARGS` itself. It fails all four copies, and a fifth with a second
    `MAVEN_ARGS`, under `gawk` and `gawk --posix` alike, and passes the real workflows.

- [x] **Step 3: commit the red guard.**

  ```bash
  git add .github/workflows/build.yml
  git commit -m "ci(#98): check both release workflows retry transient registry errors"
  ```

### Task 3: the setting, green (AC004)

**Files:** modify `.github/workflows/project-release.yml` (job `release`, `env:`) and
`.github/workflows/project-hotfix.yml` (job `hotfix`, `env:`).

- [x] **Step 1: add the `MAVEN_ARGS` block from §2.1 to both jobs, verbatim, comment included.**

- [x] **Step 2: run the guard's script again, green.** Expected: `Both release workflows retry
  transient registry errors.` and exit 0.

- [x] **Step 3: run the existing interpolation check**, which must stay green. The new lines sit
  in `env:`, not in a `run:` body:

  ```bash
  sh .github/scripts/check-run-interpolation.test.sh && sh .github/scripts/check-run-interpolation.sh
  ```

- [x] **Step 4: confirm the folded value.** It must be one line, with the two `-D` flags
  separated by a single space. Check it with any YAML parser to hand, or by reading the block:
  `>-` folds the two lines with a space and strips the trailing newline.

- [x] **Step 5: commit.**

  ```bash
  git add .github/workflows/project-release.yml .github/workflows/project-hotfix.yml
  git commit -m "fix(#98): retry transient registry errors during release and hotfix"
  ```

- [ ] **Step 6: push and open the PR into `master`.** `build.yml` runs the guard on the PR.

### Task 4: rehearsal after the merge (AC006)

Consumers call the workflows at `@master`, so a rehearsal before the merge would exercise the old
version. This task runs after the PR is merged.

- [ ] **Step 1:** dispatch DSH's `release.yml` with `dry_run: true`, using the inputs of its last
  rehearsal. Expected: green. In a rehearsal `release:perform` does not fork, because
  `-DdryRun=true` creates no `target/checkout` (see the comment above `Rehearsal tag bridge` in
  `project-release.yml`). The forks that run are `release:prepare`'s, in the `Maven Release`
  step, and the `rehearsal-tag` action's build. Both inherit `MAVEN_ARGS`, so a bad flag would
  surface there. `MAVEN_ARGS` is environment, so it never shows in a logged command line.
- [ ] **Step 2:** comment the run URL on `#98`.

A dry run deploys nothing, so it cannot show a retry. Probe A carries that claim.

## 5. Out of scope

- `project-stage.yml`, `project-staging.yml` and `deploy.yml` (§2.1).
- Any POM change, and any change to `<arguments>`.
- Recovering automatically from a release that has already failed halfway (§2.4).

## 6. Probe results

Run on 2026-10-03, Maven 3.9.16 and JDK 17.0.20.1, in a scratch directory outside the repository.

**Probe A (AC001).** Red exit 1, with the 0.3.1 failure reproduced word for word:
`Could not transfer artifact probe:probe-a:pom:1.0 from/to fake (http://127.0.0.1:8099/repo):
status code: 500, reason phrase: Internal Server Error (500)`. The registry saw one PUT of the
`.pom`:

```text
PUT /repo/probe/probe-a/1.0/probe-a-1.0.pom -> 500
```

Green exit 0 (`BUILD SUCCESS`). The same `.pom` was retried, and the rest of the deploy followed:

```text
PUT /repo/probe/probe-a/1.0/probe-a-1.0.pom -> 500
PUT /repo/probe/probe-a/1.0/probe-a-1.0.pom -> 201
PUT /repo/probe/probe-a/1.0/probe-a-1.0.pom.sha1 -> 201
PUT /repo/probe/probe-a/1.0/probe-a-1.0.pom.md5 -> 201
GET /repo/probe/probe-a/maven-metadata.xml -> 404
PUT /repo/probe/probe-a/maven-metadata.xml -> 201
PUT /repo/probe/probe-a/maven-metadata.xml.sha1 -> 201
PUT /repo/probe/probe-a/maven-metadata.xml.md5 -> 201
```

**Probe B (AC002).** Each run logged `Executing goals 'validate'...`, so the rule ran in the fork.

| Run | Exit | Fork result |
|---|---|---|
| red, nothing set | 1 | `Property "probe" is required for this build.` |
| control, `-Dprobe=x` on the outer `mvn` | 1 | `Property "probe" is required for this build.` |
| green, `MAVEN_ARGS='-Dprobe=x'` | 0 | `BUILD SUCCESS` |

The control failing confirms §1.5: a `-D` on the outer command line does not reach the fork, and
`MAVEN_ARGS` does.

**Probe C (AC003).** `same`: with and without the setting, the capture printed exactly
`3.11.0-SNAPSHOT`.
