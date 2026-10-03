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
count. Maven's own `mvn` script appends `MAVEN_ARGS` to every invocation, and the release plugin's
forked build inherits the environment, so the setting reaches the `deploy` that
`release:perform` forks. A `build.yml` check keeps the line from being dropped. No POM change, no
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
   `Retry-After` header, when the server sends one, takes precedence over the interval.
4. **`maven-deploy-plugin` 3.1.4 still has `retryFailedDeploymentCount`, and it is the wrong
   tool.** It re-runs the deploy of the whole module, so files that already went up are PUT
   again. GitHub Packages answers a second upload of a release version's file with 409 Conflict,
   so that retry can fail on a file that had succeeded.
5. **A `-D` on the outer `mvn` does not reach the release fork.** The fork's command line comes
   from `<arguments>` (root `pom.xml`, overridden in `products/pom.xml`). The `mvn` the fork
   launches is the same Maven 3.9.16 script, though, and it reads `MAVEN_ARGS` from the
   inherited environment (`bin/mvn`, line 216: `${CLASSWORLDS_LAUNCHER} ${MAVEN_ARGS} "$@"`).
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
      # command: Maven's mvn script appends it to every invocation, and release:perform's
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
`Check the reusable workflows declare no service containers` and follows that check's shape.

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

- [ ] **Step 1: write the fake registry.** It answers the first PUT of each `.pom` with 500 and
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

- [ ] **Step 2: write probe A.** It's a release-version POM-packaged project, so the only upload
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

- [ ] **Step 3: red.** Deploy without the setting:

  ```bash
  (cd probe-a && mvn -B deploy -DaltDeploymentRepository=fake::http://127.0.0.1:8099/repo) \
    > probe-a-red.log 2>&1; echo "exit=$?"
  ```

  Expected: non-zero exit; the log names `status code: 500`; `fake-registry.log` shows one
  `PUT /repo/probe/probe-a/1.0/probe-a-1.0.pom -> 500` and no second PUT of that path.

- [ ] **Step 4: green.** Restart the fake registry so its memory is empty, then deploy with the
  setting:

  ```bash
  (cd probe-a && MAVEN_ARGS="$RETRY" mvn -B deploy \
    -DaltDeploymentRepository=fake::http://127.0.0.1:8099/repo) > probe-a-green.log 2>&1; echo "exit=$?"
  ```

  Expected: exit 0; `fake-registry.log` shows the `.pom` path twice, `-> 500` then `-> 201`.

- [ ] **Step 5: write probe B.** It's a `SNAPSHOT` in a local git repository whose only check is
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

- [ ] **Step 6: red, then the control, then green.** Each run is `release:prepare -DdryRun=true`,
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

- [ ] **Step 7: probe C.** In this parent-poms checkout, the version capture used by both
  workflows prints the same thing with and without the setting:

  ```bash
  a=$(mvn -q help:evaluate -Dexpression=project.version -DforceStdout -N)
  b=$(MAVEN_ARGS="$RETRY" mvn -q help:evaluate -Dexpression=project.version -DforceStdout -N)
  [ "$a" = "$b" ] && [ "$a" = "3.11.0-SNAPSHOT" ] && echo same || echo "DIFFERENT: '$a' vs '$b'"
  ```

  Expected: `same`.

- [ ] **Step 8: stop the fake registry.** Kill the `java FakeRegistry.java` process by its PID,
  captured with `echo $!` right after the start in step 1 and again after the restart in step 4.

- [ ] **Step 9: record the outcome.** Add §6, "Probe results", to this spec: each probe's exit
  code and the relevant `fake-registry.log` lines. Commit:

  ```bash
  git add specs/98-retry-transient-registry-errors.md
  git commit -m "docs(#98): record the local retry probes"
  ```

### Task 2: the guard, red first (AC005)

**Files:** modify `.github/workflows/build.yml`, inserting after the
`Check the reusable workflows declare no service containers` step.

- [ ] **Step 1: add the step.**

  ```yaml
      # #98: a release's deploy must retry a transient 5xx from GitHub Packages. The retry
      # lives in one MAVEN_ARGS line per release workflow (see specs/98-...md §2.1), and
      # nothing else would notice it was gone until the next 500 split a release in half.
      - name: Check the release workflows retry transient registry errors
        run: |
          set -euo pipefail
          status=0
          for f in .github/workflows/project-release.yml .github/workflows/project-hotfix.yml; do
            for want in \
                '-Daether.connector.http.retryHandler.serviceUnavailable=429,500,502,503,504' \
                '-Daether.connector.http.retryHandler.count=5'; do
              if ! grep -qF -- "$want" "$f"; then
                echo "::error file=$f::$f does not set $want in MAVEN_ARGS (see #98)."
                status=1
              fi
            done
          done
          [ "$status" -eq 0 ] && echo "Both release workflows retry transient registry errors."
          exit "$status"
  ```

- [ ] **Step 2: run it locally, red.** Extract the `run:` body to a scratch script and run it
  from the repository root. Expected: four `::error` lines, two per file, and exit 1.

- [ ] **Step 3: commit the red guard.**

  ```bash
  git add .github/workflows/build.yml
  git commit -m "ci(#98): check both release workflows retry transient registry errors"
  ```

### Task 3: the setting, green (AC004)

**Files:** modify `.github/workflows/project-release.yml` (job `release`, `env:`) and
`.github/workflows/project-hotfix.yml` (job `hotfix`, `env:`).

- [ ] **Step 1: add the `MAVEN_ARGS` block from §2.1 to both jobs, verbatim, comment included.**

- [ ] **Step 2: run the guard's script again, green.** Expected: `Both release workflows retry
  transient registry errors.` and exit 0.

- [ ] **Step 3: run the existing interpolation check**, which must stay green. The new lines sit
  in `env:`, not in a `run:` body:

  ```bash
  sh .github/scripts/check-run-interpolation.test.sh && sh .github/scripts/check-run-interpolation.sh
  ```

- [ ] **Step 4: confirm the folded value.** It must be one line, with the two `-D` flags
  separated by a single space. Check it with any YAML parser to hand, or by reading the block:
  `>-` folds the two lines with a space and strips the trailing newline.

- [ ] **Step 5: commit.**

  ```bash
  git add .github/workflows/project-release.yml .github/workflows/project-hotfix.yml
  git commit -m "fix(#98): retry transient registry errors during release and hotfix"
  ```

- [ ] **Step 6: push and open the PR into `master`.** `build.yml` runs the guard on the PR.

### Task 4: rehearsal after the merge (AC006)

Consumers call the workflows at `@master`, so a rehearsal before the merge would exercise the old
version. This task runs after the PR is merged.

- [ ] **Step 1:** dispatch DSH's `release.yml` with `dry_run: true`, using the inputs of its last
  rehearsal. Expected: green, and the `Maven Release Perform` step's log shows the fork's command
  line with no error about the new flags.
- [ ] **Step 2:** comment the run URL on `#98`.

A dry run deploys nothing, so it cannot show a retry. Probe A carries that claim.

## 5. Out of scope

- `project-stage.yml`, `project-staging.yml` and `deploy.yml` (§2.1).
- Any POM change, and any change to `<arguments>`.
- Recovering automatically from a release that has already failed halfway (§2.4).
