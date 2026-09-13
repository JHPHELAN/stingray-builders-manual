# Stormy the Stingray — Full-Disk Backup Log

Tier-2 weekly full-disk backups per Chapter 20.4 of the Builder's Manual.

- **Target drive:** Sabrent USB adapter (JMicron JMS578, USB ID `152d:a578`) + Seagate ST3160812AS 160 GB HDD (149 GiB usable), single exFAT partition, UUID `7F33-6797`.
- **Filename convention:** `nvme_{boot,root}_YYYY-MM-DD.img.gz`
- **Recipe:** `sudo sh -c 'dd if=/dev/nvme0n1pN bs=4M conv=sync,noerror status=progress | gzip -1 > /mnt/backup/nvme_X_YYYY-MM-DD.img.gz'`
- **Verify each image with:** `gzip -t <file> && echo OK`

## Backup history

| Date       | Boot img (raw / gz) | Root img (raw / gz) | Throughput | Verified | Notes |
|------------|---------------------|---------------------|------------|----------|-------|
| 2026-07-31 | 512 MB / 168 MB     | 238 GiB / 13 GB     | 114 MB/s (USB 3.0) | `gzip -t` OK on both | First backup after Manual v1.0. Discovered `mount -t exfat` gotcha on Ubuntu 24.04 — see Field Note 104. |
