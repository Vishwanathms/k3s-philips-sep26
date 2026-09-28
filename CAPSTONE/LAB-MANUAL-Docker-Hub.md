# Capstone — Publish the app images to Docker Hub

**Prerequisite lab · ~45 min · do this once, then every stage can use it**

## Scenario

Stage 07 pushed the two capstone images to a **local registry** on your own VM
(`localhost:5000`). That works for a single-node lab, but nothing outside your
VM can pull from it.

In this lab you publish the same two images to **Docker Hub** instead: you
create an account, log in from the CLI with an access token, build both apps,
push them, and point the manifests at your own namespace so k3s pulls them
from the internet.

Docker Hub is the default registry every `docker pull` uses when an image has
no registry prefix — `redis:7-alpine` really means
`docker.io/library/redis:7-alpine`. After this lab, **your** images are
addressable the same way.

## Learning objectives

By the end you can:

- create a Docker Hub account and a scoped **access token**, and explain why a token beats your password
- log in from the CLI, and say where Docker stored the credential and in what form
- read an image reference (`docker.io/<user>/capstone-api:1.0.0`) field by field
- build, tag and push both capstone images, and verify them from the registry API
- repoint the manifests at your Docker Hub namespace by changing two lines
- explain what changes when the repository is **private**, and create the `imagePullSecret` it needs

## Before starting

```bash
cd ~/Documents/k3s-training          # the course repo
docker version                       # Client AND Server lines
kubectl get nodes                    # Ready
curl -s -o /dev/null -w '%{http_code}\n' https://hub.docker.com/    # 200 - you have internet
```

You need a working email address you can read right now — Docker Hub requires
email verification before your first push.

---

# Part A — Get an identity on Docker Hub (15 min)

## A1 — Create the account

1. Open **https://hub.docker.com/signup**.
2. Choose a **Docker ID**. This is not just a login — it becomes the
   **namespace of every image you push**, forever, in public. Pick something
   you're happy to show a future employer: `vishwa-k3s`, not `test123`.
   - lowercase letters, digits and `-`, 4–30 characters
   - it **cannot be changed** later, and a deleted ID is not released for reuse
3. Verify the email Docker sends you. **Push fails until you do.**
4. Sign in at **https://hub.docker.com/**.

Record your ID — every command below uses it:

```bash
export DOCKERHUB_USER=<your-docker-id>       # e.g. vishwa-k3s
echo $DOCKERHUB_USER
```

> **Checkpoint A1:** you are signed in to hub.docker.com and
> `echo $DOCKERHUB_USER` prints your ID in lowercase.

## A2 — Create an access token, not a password

In the web UI: **your avatar → Account settings → Personal access tokens →
Generate new token**.

| Field | Use |
|---|---|
| Description | `k3s-training-laptop` — name it after the *machine*, so you can revoke one machine without touching the others |
| Expiration | 30 days is plenty for this course |
| Access permissions | **Read & Write** (you need to push; you do **not** need Delete) |

Copy the token **now**. Docker Hub shows it exactly once.

**Why a token and not your password?** Three concrete reasons:

| | Password | Access token |
|---|---|---|
| Scope | your whole account, including billing and org membership | only registry read/write |
| Revocable alone | no — you'd change your password everywhere | yes, revoke one token, other machines keep working |
| Works with 2FA | no — once 2FA is on, `docker login` with a password fails | yes, this is the supported path |

Keep it out of your shell history. Read it into a variable without echoing it:

```bash
read -rsp 'Paste your Docker Hub token: ' DOCKERHUB_TOKEN; echo
```

> **Never** put a token in a Dockerfile, a manifest, a `kustomization.yaml`, or
> a git commit. Bots scan public repositories for exactly this, within minutes.

## A3 — Log in from the CLI

Pipe the token in on stdin so it never appears as a command argument (command
arguments are visible to every other user on the machine via `ps`):

```bash
echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin
```

Expected:

```
WARNING! Your password will be stored unencrypted in /home/you/.docker/config.json.
Configure a credential helper to remove this warning. See
https://docs.docker.com/go/credential-store/

Login Succeeded
```

Read the warning, then see for yourself what it means:

```bash
cat ~/.docker/config.json
```

Expected — an `auths` entry for Docker Hub holding a base64 blob:

```json
{
  "auths": {
    "https://index.docker.io/v1/": {
      "auth": "dmlzaHdhLWszczpka3Rf..."
    }
  }
}
```

That value is **base64, not encryption** — anyone who reads this file has your
token. Prove it:

```bash
grep -o '"auth": "[^"]*"' ~/.docker/config.json | cut -d'"' -f4 | base64 -d; echo
```

Expected: `your-docker-id:dckr_pat_...` in plain text. This is why step D3
uses this same file to build a Kubernetes `imagePullSecret`, and why you run
`docker logout` on a shared machine when you're done.

> **Checkpoint A3:** `Login Succeeded`, and you can explain what's in
> `~/.docker/config.json` and why the warning appears.

---

# Part B — Build the two app images (10 min)

## B1 — Understand the name before you type it

Both images get a name with four parts:

```
docker.io / vishwa-k3s / capstone-api : 1.0.0
└───┬────┘  └────┬────┘  └─────┬────┘  └─┬─┘
 registry    your Docker   repository    tag
 (implied     ID = the      name
  default)    namespace
```

Two rules that catch people out:

- **No registry prefix means `docker.io`.** So `vishwa-k3s/capstone-api:1.0.0`
  and `docker.io/vishwa-k3s/capstone-api:1.0.0` are the same image. Contrast
  with stage 07's `localhost:5000/capstone-api:1.0.0`, where the prefix was
  the whole point.
- **Docker Hub allows exactly one level of nesting.** `vishwa-k3s/capstone-api`
  is valid; `vishwa-k3s/capstone/api` is not. To group images, use a prefix in
  the repository name (`capstone-api`, `capstone-web`), which is what this lab
  does.

Set the image names once:

```bash
export API_IMAGE=docker.io/$DOCKERHUB_USER/capstone-api:1.0.0
export WEB_IMAGE=docker.io/$DOCKERHUB_USER/capstone-web:1.0.0
echo "$API_IMAGE"; echo "$WEB_IMAGE"
```

## B2 — Build

The build context is the directory holding each `Dockerfile`; everything in it
is sent to the daemon, minus whatever `.dockerignore` excludes.

```bash
docker build -t "$API_IMAGE" CAPSTONE/app/api
docker build -t "$WEB_IMAGE" CAPSTONE/app/web
docker images | grep capstone
```

Expected (sizes approximate):

```
vishwa-k3s/capstone-web   1.0.0   ...   73.7MB
vishwa-k3s/capstone-api   1.0.0   ...   191MB
```

Note that `docker images` prints the name **without** `docker.io/` — the CLI
hides the default registry. It's the same image.

Both Dockerfiles already run as non-root ([app/api/Dockerfile](app/api/Dockerfile)
uses `USER 10001`; [app/web/Dockerfile](app/web/Dockerfile) uses the
`nginx-unprivileged` base on port 8080). Nothing about publishing changes that.

## B3 — Tag it a second time, on purpose

One image can carry many names. Add a moving `1.0` tag alongside the exact
`1.0.0`:

```bash
docker tag "$API_IMAGE" docker.io/$DOCKERHUB_USER/capstone-api:1.0
docker tag "$WEB_IMAGE" docker.io/$DOCKERHUB_USER/capstone-web:1.0
docker images --format '{{.Repository}}:{{.Tag}}  {{.ID}}' | grep capstone
```

Expected — **four names, two image IDs**:

```
vishwa-k3s/capstone-api:1.0.0  a1b2c3d4e5f6
vishwa-k3s/capstone-api:1.0    a1b2c3d4e5f6     <- same ID
vishwa-k3s/capstone-web:1.0.0  f6e5d4c3b2a1
vishwa-k3s/capstone-web:1.0    f6e5d4c3b2a1     <- same ID
```

A tag is a **label pointing at an image**, not a copy. Pushing both costs one
upload of the layers plus one tiny manifest.

**Why the manifests never use `latest`:** an image reference with no tag means
`:latest`, and Kubernetes then defaults `imagePullPolicy` to `Always` — every
Pod restart re-hits the registry, and two Pods started a week apart can silently
run different code. An explicit tag defaults to `IfNotPresent` and is
reproducible. Keep `1.0.0` in the manifests.

> **Checkpoint B3:** four names, two IDs, and you can explain why
> `docker images` doesn't show `docker.io/`.

---

# Part C — Push and verify (10 min)

## C1 — Push

```bash
docker push docker.io/$DOCKERHUB_USER/capstone-api:1.0.0
docker push docker.io/$DOCKERHUB_USER/capstone-api:1.0
docker push docker.io/$DOCKERHUB_USER/capstone-web:1.0.0
docker push docker.io/$DOCKERHUB_USER/capstone-web:1.0
```

Expected on the first push — layers upload; on the second, they don't:

```
The push refers to repository [docker.io/vishwa-k3s/capstone-api]
5f70bf18a086: Pushed
a1b2c3d4e5f6: Pushed
1.0.0: digest: sha256:9c1f... size: 1573

The push refers to repository [docker.io/vishwa-k3s/capstone-api]
5f70bf18a086: Layer already exists
a1b2c3d4e5f6: Layer already exists
1.0: digest: sha256:9c1f... size: 1573     <- identical digest
```

`Layer already exists` and the **identical `sha256:` digest** are the proof of
step B3: the second tag uploaded no image data. The digest is the image's real,
content-addressed identity; tags are mutable, digests are not.

> **First push created the repository, and it is PUBLIC.** Docker Hub creates
> a repository implicitly on first push, and the default is public. Anyone can
> now pull your image. That's fine for this course — the images hold no
> secrets. To keep them private, see C4.

## C2 — Verify from outside Docker

Don't trust `docker images` — ask the registry what it actually holds. Docker
Hub's public read API needs an anonymous pull token first:

```bash
TOKEN=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$DOCKERHUB_USER/capstone-api:pull" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

curl -s -H "Authorization: Bearer $TOKEN" \
  https://registry-1.docker.io/v2/$DOCKERHUB_USER/capstone-api/tags/list
```

Expected:

```json
{"name":"vishwa-k3s/capstone-api","tags":["1.0","1.0.0"]}
```

Also check it in the browser: **https://hub.docker.com/r/\<your-id\>/capstone-api**
→ the **Tags** tab shows both tags, their sizes and push times.

## C3 — Prove k3s can pull it

k3s does not use Docker. It runs its own containerd, with its own image store
and its own credentials. Your `docker login` means nothing to it — but these
repositories are public, so no configuration is needed. Verify with k3s's own
tool, not Docker's:

```bash
sudo k3s crictl rmi docker.io/$DOCKERHUB_USER/capstone-api:1.0.0 2>/dev/null   # force a real pull
sudo k3s crictl pull docker.io/$DOCKERHUB_USER/capstone-api:1.0.0
sudo k3s crictl images | grep capstone
```

Expected:

```
Image is up to date for sha256:9c1f...
docker.io/vishwa-k3s/capstone-api   1.0.0   9c1f...   191MB
```

That `sha256` must match the digest `docker push` printed in C1. Same bytes,
fetched over the internet by the cluster's own runtime.

> **Checkpoint C3:** `crictl images` lists your image, and its digest matches
> the one from `docker push`.

## C4 — Optional: make it private instead

Public is the right choice for this course. If you want to practise the
private path — which is what any real workplace uses:

1. **https://hub.docker.com/r/\<your-id\>/capstone-api** → **Settings** →
   **Make private**. (Free accounts include a limited number of private
   repositories; check your plan page for the current allowance.)
2. Prove the cluster can no longer pull it:

   ```bash
   sudo k3s crictl rmi docker.io/$DOCKERHUB_USER/capstone-api:1.0.0
   sudo k3s crictl pull docker.io/$DOCKERHUB_USER/capstone-api:1.0.0
   ```

   Expected failure — note that it says *not found*, not *unauthorized*. A
   private registry hides existence from anonymous callers:

   ```
   FATA[0001] pulling image: failed to pull and unpack image "...": failed to resolve
   reference "docker.io/vishwa-k3s/capstone-api:1.0.0": ... not found
   ```

3. Give the namespace a pull credential, built from the `~/.docker/config.json`
   you inspected in A3:

   ```bash
   kubectl -n capstone create secret docker-registry dockerhub \
     --docker-server=https://index.docker.io/v1/ \
     --docker-username="$DOCKERHUB_USER" \
     --docker-password="$DOCKERHUB_TOKEN"
   ```

4. Attach it. A Secret is not used unless something references it — the
   tidiest way is to put it on the ServiceAccount every Pod in the namespace
   already uses:

   ```bash
   kubectl -n capstone patch serviceaccount default \
     -p '{"imagePullSecrets":[{"name":"dockerhub"}]}'
   ```

   (The per-Deployment alternative is `spec.template.spec.imagePullSecrets`.
   Day 11 gives each tier its own ServiceAccount and moves it there.)

5. Recreate the Pods so they retry the pull with the credential:

   ```bash
   kubectl -n capstone rollout restart deploy/api deploy/web
   ```

---

# Part D — Point the manifests at your images (10 min)

## D1 — Change the two lines that decide the registry

The Deployments say only `image: capstone-api` / `image: capstone-web`. The
registry and tag live in **one file per stage**, `kustomization.yaml`:

Work in the stage you are currently on — find its `kustomization.yaml`:

```bash
find CAPSTONE -name kustomization.yaml
cd CAPSTONE/<your-stage>/manifests
grep -A2 'name: capstone' kustomization.yaml
```

Currently:

```yaml
  - name: capstone-api
    newName: localhost:5000/capstone-api
    newTag: 1.0.0
```

Change the two `newName:` lines to your namespace — by hand in an editor, or:

```bash
sed -i "s|newName: localhost:5000/|newName: docker.io/$DOCKERHUB_USER/|" kustomization.yaml
```

## D2 — Render before you apply

`kubectl kustomize` shows exactly what would be sent to the API server. Always
read this before applying a registry change:

```bash
kubectl kustomize . | grep 'image:'
```

Expected:

```
        image: docker.io/vishwa-k3s/capstone-api:1.0.0
        image: docker.io/vishwa-k3s/capstone-web:1.0.0
        image: redis:7-alpine
```

`redis:7-alpine` is untouched — it has no `newName` entry, so it still comes
from Docker Hub's official `library` namespace.

> **Checkpoint D2:** the two capstone images carry **your** Docker ID, and the
> tag is `1.0.0`, not `latest`.

## D3 — Apply and confirm the cluster used Docker Hub

```bash
kubectl apply -k .
kubectl -n capstone rollout status deploy/api
kubectl -n capstone rollout status deploy/web

# What is actually running:
kubectl -n capstone get pods -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image

# The pull event, from the cluster's point of view:
kubectl -n capstone describe pod -l app=api | grep -E 'Pulling|Pulled' | tail -2
```

Expected:

```
POD        IMAGE
api-...    docker.io/vishwa-k3s/capstone-api:1.0.0
web-...    docker.io/vishwa-k3s/capstone-web:1.0.0

Pulling image "docker.io/vishwa-k3s/capstone-api:1.0.0"
Successfully pulled image "docker.io/vishwa-k3s/capstone-api:1.0.0" in 4.2s
```

Then check the app itself still works:

```bash
export NODE_IP=$(hostname -I | awk '{print $1}')
curl -s --resolve capstone.k3s.local:80:$NODE_IP http://capstone.k3s.local/api/hits; echo
```

Expected: the counter continues from wherever it was — you changed **where the
image came from**, not the app or its data.

> **Checkpoint D3:** the Pods' images show your Docker ID, and the hit counter
> did not reset.

## D4 — Ship a change, end to end

The loop you'll repeat for the rest of the course. Bump the version, rebuild,
push a new tag, and roll it out:

```bash
export TAG=1.0.1
docker build -t docker.io/$DOCKERHUB_USER/capstone-api:$TAG CAPSTONE/app/api
docker push docker.io/$DOCKERHUB_USER/capstone-api:$TAG

cd CAPSTONE/<your-stage>/manifests
sed -i "/name: capstone-api/,+2 s/newTag: .*/newTag: $TAG/" kustomization.yaml
kubectl kustomize . | grep capstone-api      # read it first
kubectl apply -k .
kubectl -n capstone rollout status deploy/api
```

**Always a new tag, never a re-pushed one.** If you overwrite `1.0.0` in place,
nodes that already cached it keep serving the old code under
`imagePullPolicy: IfNotPresent`, and you get a cluster where different Pods run
different builds of the "same" image. That's among the hardest classes of bug
to diagnose.

> **Checkpoint D4:** `kubectl -n capstone get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}'`
> ends in `:1.0.1`, and the rollout completed without downtime.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `denied: requested access to the resource is denied` on push | the image name's namespace isn't your Docker ID (typo, or uppercase), or you're not logged in. Check `docker images \| grep capstone` and re-run `docker login` |
| `unauthorized: incorrect username or password` at login | you pasted the token with a trailing newline or used your password with 2FA enabled. Generate a fresh token and use `--password-stdin` |
| push hangs then fails with `email must be verified` | click the link in Docker's signup email, then retry |
| `toomanyrequests: You have reached your pull rate limit` | anonymous pulls are rate-limited per IP, and **k3s pulls anonymously even when Docker is logged in**. Fix by giving the namespace the `imagePullSecret` from C4 — authenticated pulls get a higher allowance |
| `ErrImagePull` / `ImagePullBackOff` in the cluster | compare the two sides: `kubectl kustomize . \| grep image:` against the Tags tab on hub.docker.com. Then `kubectl -n capstone describe pod <pod>` and read the last event |
| `ImagePullBackOff` with `not found` on a repo you can see in the browser | the repository is private; the cluster pulls anonymously. Do C4 |
| `exec format error` in the Pod logs, image pulled fine | the image was built for a different CPU architecture than the node. Build with `docker buildx build --platform linux/amd64 -t ... --push .` |
| Pods still run the old code after a push | you re-pushed an existing tag. Push a new tag and update `newTag` (D4) |
| `manifest unknown` on `crictl pull` | the tag doesn't exist in the registry. Re-check C2's tags list |

## Before you leave

Your images are on Docker Hub and the manifests point at them. Two housekeeping
notes:

```bash
# On a shared or lab machine, drop the stored credential:
docker logout

# Revoke the token when the course ends:
#   hub.docker.com -> Account settings -> Personal access tokens -> Delete
```

Nothing in the repository contains your token — confirm it before you commit:

```bash
git grep -nI 'dckr_pat' || echo "clean: no tokens committed"
```

Day 13 replaces Docker Hub with **Harbor**, a registry you run yourself, with
TLS and projects. When it does, you'll change the same two `newName:` lines.
