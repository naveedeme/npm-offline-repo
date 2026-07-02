# NPM Offline Repository

Build and ship a portable npm repository for offline Linux systems.

This project creates:

- a Verdaccio registry storage bundle
- a populated npm cache
- `nvm` plus a Linux Node.js runtime tarball
- exact `package-lock.json` files for each package set
- optional prebuilt `node_modules` tarballs
- install and verification scripts for the offline machine

The goal is to let an offline computer install packages from a local npm registry at `http://localhost:4873`, or from another computer on the same LAN.

## Package Sets

| Folder | Package set |
|---|---|
| `react-vite` | React + Vite application stack |
| `nextjs` | Next.js application stack |
| `vuejs-vite` | Vue + Vite application stack |
| `nuxt` | Nuxt application stack |
| `angular` | Angular application stack |
| `svelte` | SvelteKit application stack |
| `remix` | Remix application stack |
| `astro` | Astro application stack |
| `gatsby` | Gatsby application stack |
| `nodejs-backend` | Node.js backend/API stack |

## Build Online

Run this on the machine that has internet access:

```bash
npm install -g verdaccio@latest
bash scripts/build-offline-repository.sh
```

The local output is written to:

```text
artifacts/
├── npm-offline-repository.tar.gz
├── SHA256SUMS.txt
└── offline-repository/
    ├── npm-cache/
    ├── package-sets/
    ├── runtimes/
    │   ├── node/
    │   └── nvm/
    ├── node_modules_by_framework/
    ├── verdaccio/
    ├── install-node-offline.sh
    ├── start-offline-registry.sh
    ├── install-from-offline-repo.sh
    └── verify-offline-repo.sh
```

The build resolves the latest package versions allowed by the package ranges in each `package.json`, then freezes the result in lockfiles.

## Ship Offline

For a USB drive or external disk, copy the full folder:

```text
artifacts/offline-repository/
```

For GitHub Releases, download the pair that matches the offline computer:

| Offline OS | Repository bundle | Prebuilt modules bundle |
|---|---|---|
| Ubuntu 22.04 | `npm-offline-repository-ubuntu-22.04.tar.gz` | `node_modules_by_framework-ubuntu-22.04.tar.gz` |
| Ubuntu 24.04 | `npm-offline-repository-ubuntu-24.04.tar.gz` | `node_modules_by_framework-ubuntu-24.04.tar.gz` |
| Ubuntu 26.04 | `npm-offline-repository-ubuntu-26.04.tar.gz` | `node_modules_by_framework-ubuntu-26.04.tar.gz` |

Each variant is built independently on its matching GitHub-hosted Ubuntu runner. Ubuntu 26.04 is currently a GitHub public preview runner image.

Extract both tarballs in the same directory:

```bash
tar -xzf npm-offline-repository-ubuntu-22.04.tar.gz
tar -xzf node_modules_by_framework-ubuntu-22.04.tar.gz
```

Replace `ubuntu-22.04` with `ubuntu-24.04` or `ubuntu-26.04` for those machines.

## Use on the Offline Linux Computer

Install the bundled `nvm`, Node.js, and npm:

```bash
./install-node-offline.sh
source ./node-env.sh
```

Install Verdaccio from the bundled npm cache:

```bash
npm install -g verdaccio --offline --cache ./npm-cache
```

Start the local registry:

```bash
./start-offline-registry.sh
```

In another terminal, install a package set into a project:

```bash
./install-from-offline-repo.sh react-vite /home/user/myapp
```

By default, the installer extracts the prebuilt `node_modules` tarball when it exists. That is the safest path for native packages. To force a fresh offline install from the registry/cache:

```bash
USE_PREBUILT=0 ./install-from-offline-repo.sh react-vite /home/user/myapp
```

## Use on a Village LAN

Run the registry on one computer:

```bash
HOST=0.0.0.0 PORT=4873 ./start-offline-registry.sh
```

On another computer, point npm to it:

```bash
npm set registry http://SERVER_IP:4873
npm install react vite express
```

Replace `SERVER_IP` with the LAN IP of the computer running Verdaccio.

## Verify Before Shipping

After building, run:

```bash
bash artifacts/offline-repository/verify-offline-repo.sh
```

This starts the offline registry and checks that every package set can install from the local registry/cache without internet.

## Important Native Package Notes

Some packages download or compile native binaries, for example `sharp`, `better-sqlite3`, `sqlite3`, `serialport`, `electron`, `cypress`, and browser automation tools.

For the most reliable result, keep these the same between the online build machine and the offline machine:

- Linux distribution and version
- CPU architecture, for example x64
- Node.js version, provided in `runtimes/node/` and installed through `nvm`
- npm version, included with the bundled Node.js runtime
- glibc version

The prebuilt `node_modules` tarballs are included for this reason. They avoid most offline rebuild problems when the target Linux environment matches the build environment.

## GitHub Release Workflow

The workflow at `.github/workflows/download-packages.yml` builds three independent variants in one release:

- `npm-offline-repository-ubuntu-22.04.tar.gz`
- `npm-offline-repository-ubuntu-24.04.tar.gz`
- `npm-offline-repository-ubuntu-26.04.tar.gz`
- `node_modules_by_framework-ubuntu-22.04.tar.gz`
- `node_modules_by_framework-ubuntu-24.04.tar.gz`
- `node_modules_by_framework-ubuntu-26.04.tar.gz`
- one `SHA256SUMS-<variant>.txt` file per variant

Manual runs let you choose the Node.js version and release tag. The selected Node.js version is downloaded into `runtimes/node/`, and `nvm` is downloaded into `runtimes/nvm/`. Pushes to `main` or `master` create a dated prerelease tag. Version tags like `v1.2.0` create versioned releases.
