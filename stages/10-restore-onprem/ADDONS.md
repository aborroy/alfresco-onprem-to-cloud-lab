# Stage 10 Addons

This stage installs addons by baking them into custom `alfresco` and `share` images.

Put addon artifacts in these folders before building Stage 10:

- `stages/10-restore-onprem/addons/repository/amps` for repository `.amp`
- `stages/10-restore-onprem/addons/repository/jars` for repository `.jar`
- `stages/10-restore-onprem/addons/share/amps` for Share `.amp`
- `stages/10-restore-onprem/addons/share/jars` for Share `.jar`

You can fetch artifacts automatically:

```bash
cd stages/10-restore-onprem
../../shared/fetch-addons.sh
```

Re-download all files:

```bash
cd stages/10-restore-onprem
../../shared/fetch-addons.sh --force
```

The script is best-effort. If an addon asset cannot be resolved from GitHub
release metadata, it prints a warning with the release page URL to download the
file manually.

Addon set from `alfresco-ubuntu-installer/ADDONS.md`:

- Google Docs Integration (3.1.0)
- OOTBee Support Tools (1.2.2.0)
- Javascript Console (0.7)
- Alfresco Share Site Creators (0.0.8)
- Alfresco Share Site Space Templates (1.1.4-SNAPSHOT)
- Alfresco Share Online Edition Addon (0.3.0)
- ESign Certification Addon (1.8.4)
- Alfresco PDF Toolkit (1.4)
- Alfresco T-Engine OCR Addon

Start Stage 10:

```bash
docker compose --env-file .env -f stages/10-restore-onprem/compose.yaml up -d --build
```
