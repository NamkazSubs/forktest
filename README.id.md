# forktest

[English](README.md) | **Bahasa Indonesia**

Runner berbasis fork untuk **suite test PHPUnit yang sudah ada**.

`processIsolation` PHPUnit (dan `@runTestsInSeparateProcesses`) memberi setiap test proses PHP sendiri. Itu pilihan
yang aman untuk suite yang memakai Mockery `alias:`/`overload:`, properti static, atau global. Tapi juga lambat: tiap
test menjalankan `php` baru, boot autoloader, dan mem-parse ulang file yang sama. Pada suite dengan ribuan test,
sebagian besar waktu habis untuk memulai proses, bukan untuk menjalankan test.

forktest mempertahankan isolasinya dan membuang biaya startup-nya. Proses induk memuat bootstrap satu kali, lalu
`pcntl_fork()` satu child per test. Test tetap dijalankan oleh `TestCase::run()` milik PHPUnit sendiri, jadi `setUp`,
`tearDown`, assertion, data provider, dan Mockery berperilaku seperti biasa. Yang berbeda hanya penjadwalan dan
isolasinya.

```
vendor/bin/forktest                      # jalankan suite dari phpunit.xml
vendor/bin/forktest tests/Unit/Services  # jalankan satu folder atau satu file
vendor/bin/forktest --filter Transfer    # hanya test yang namanya cocok
vendor/bin/forktest --fast               # lebih cepat lagi, isolasi lebih lemah (lihat di bawah)
vendor/bin/forktest --changed            # hanya test yang terdampak perubahan git kamu (lihat di bawah)
```

## Hasil

Diukur satu kali pada project Lumen 5.8 (PHP 7.3.33, PHPUnit 7.0.0, 4 core, 332 file test, 6.954 test,
`processIsolation="true"`):

| Runner                           | Full suite            | Catatan                                         |
|----------------------------------|-----------------------|-------------------------------------------------|
| `phpunit`                        | sekitar 17 menit      | ekstrapolasi dari slice 445 test yang diukur, tidak dijalankan penuh |
| `paratest -p4`                   | 363 detik             | diukur                                          |
| `forktest`                       | **48 detik**          | diukur, terisolasi per test                     |
| `forktest --fast`                | **22 detik**          | diukur, lihat catatan di bawah                  |

Setiap run forktest yang diukur melaporkan total dan daftar test gagal yang sama dengan ParaTest
(6.954 test, 14.453 assertion, 546 error, 15 failure, 1 risky, 68 skipped; ParaTest menghitung satu test risky itu
sebagai error, makanya di sana 547). Full suite hanya dibandingkan dengan ParaTest; `phpunit` murni tidak dijalankan
di sana. Pada slice 445 test (`tests/Unit/Repositories`) yang dijalankan dengan `phpunit` sendiri (57,6 detik vs
2,7 detik untuk forktest), 14 test yang gagal sama di keduanya dan gagal karena sebab yang tidak berhubungan dengan
runner (misalnya `connection() on null`).

Ini run tunggal di satu mesin. Perkirakan noise sekitar 10%, dan angka yang berbeda di suite lain.

## Cara kerja

1. **Bootstrap sekali.** Proses induk membaca `phpunit.xml`, menerapkan bagian `<php>`-nya (env, ini, const, var,
   server), lalu me-require file bootstrap. Ia tidak pernah memuat file test.
2. **Discovery di child.** Satu child per file memuat file itu, membangun `TestSuite` PHPUnit (sehingga data provider
   ikut berjalan), dan melaporkan nama-nama test ke induk.
3. **Satu fork per test.** Setiap test berjalan di child sendiri, yang memuat file-nya sendiri, menjalankan
   `TestCase::run()`, mengirim hasilnya lewat socket, lalu keluar. Paling banyak `--jobs` child berjalan bersamaan.
4. **Opcache.** `opcache.enable_cli` tidak bisa diatur lewat `ini_set()`, jadi forktest menjalankan ulang dirinya
   sekali dengan `-d opcache.enable_cli=1` kalau ekstensinya tersedia. Child hasil fork berbagi script yang sudah
   dikompilasi. Hanya proses forktest sendiri yang terpengaruh; `php.ini` dan PHP-FPM atau aplikasi web yang sedang
   berjalan tidak tersentuh. Pakai `--no-opcache` untuk melewati langkah ini.

Kenapa induk tidak boleh memuat file test atau kelas aplikasi: test yang memakai Mockery `alias:` atau `overload:`
gagal dengan "class already exists" kalau kelas aslinya sudah dimuat sebelum fork. Menjaga induk tetap bersih itulah
yang membuat isolasinya setara dengan proses baru.

### `--fast`

Dengan `--fast`, semua test dalam satu file berjalan berurutan di satu proses, jadi tiap file hanya butuh satu fork,
bukan satu per test. File yang mengandung `alias:`/`overload:` tetap diisolasi per test, dan kalau worker bersama mati
(misalnya karena fatal error), test yang belum selesai dijalankan ulang secara terisolasi.

Konsekuensinya: test dalam satu file bisa saling melihat properti static, global, dan singleton, sama seperti PHPUnit
tanpa isolasi. Suite di atas kebetulan memberi hasil identik di kedua mode, tapi self-test bawaan berisi dua test yang
sengaja bergantung pada isolasi, dan `--fast` menggagalkan salah satunya. Pakai `--fast` untuk siklus edit-lalu-jalankan
dan biarkan mode default untuk CI.

## Persyaratan

- PHP 7.3 atau lebih baru dengan `pcntl` dan `posix` (Linux atau macOS; Windows tidak didukung).
- PHPUnit dan kode yang dites terpasang di project, dimuat oleh bootstrap project atau `vendor/autoload.php`.
- Opsional: ekstensi `Zend OPcache`.

Yang sudah diuji:

| Kombinasi                                     | Yang diperiksa                                                          |
|-----------------------------------------------|-------------------------------------------------------------------------|
| PHP 7.3.33 + PHPUnit 7.0.0, suite nyata 6.954 test | full run vs ParaTest: total dan test gagal sama                    |
| PHP 7.4.33 + PHPUnit 7.0.0, suite yang sama   | full run vs ParaTest: sama kecuali satu kasus opcache (lihat di bawah)  |
| PHP 7.3.33 + PHPUnit 7.5.20, fixture bawaan   | `composer install`, selftest, total sama dengan milik PHPUnit sendiri   |

forktest memanggil bagian internal PHPUnit (`TestSuite`, `TestResult`, `PHPUnit\Util\Test::getHookMethods`), jadi
PHPUnit 8 ke atas, dan PHP 8, belum diuji dan mungkin tidak jalan.

## Instalasi

Belum ada di Packagist. Pilih salah satu:

**A. Composer, dari repository git**

```bash
composer config repositories.forktest vcs git@github.com:<akun-kamu>/forktest.git
composer require --dev forktest/forktest:dev-main
vendor/bin/forktest
```

Sebelum push, ganti vendor `forktest` di `composer.json` dan di perintah di atas dengan milikmu.

**B. Clone lalu jalankan, tanpa Composer**

```bash
git clone git@github.com:<akun-kamu>/forktest.git ~/tools/forktest
cd /path/ke/project-kamu
php ~/tools/forktest/bin/forktest
```

Opsional, tambahkan `alias forktest='php ~/tools/forktest/bin/forktest'` ke profil shell.

forktest selalu berjalan dari root project (folder yang berisi `phpunit.xml`).

## Penggunaan

```
forktest [options] [path ...]

  path                  file atau folder test (default: folder testsuite di phpunit.xml)

  -j, --jobs N          jumlah worker paralel (default: jumlah core CPU)
      --filter REGEX    hanya jalankan test yang namanya cocok dengan REGEX
      --group NAME      hanya jalankan test dalam @group ini (pisahkan dengan koma, boleh diulang); test tanpa
                        group masuk ke group "default"
      --exclude-group NAME
                        lewati test dalam @group ini (pisahkan dengan koma, boleh diulang)
      --timeout SEC     hentikan test yang tidak menghasilkan hasil selama SEC detik (default 120)
      --stop-on-failure berhenti di error atau failure pertama (juga aktif lewat stopOnFailure="true" di phpunit.xml)
      --log-junit FILE  tulis laporan JUnit XML ke FILE
      --record-map FILE rekam file project yang dimuat tiap file test (full run; menulis peta dampak)
      --changed         hanya jalankan file test yang terdampak perubahan sejak merge-base dengan master/main
      --since REF       seperti --changed, tapi terhadap ref git yang diberikan (branch, tag, atau commit)
      --map FILE        peta dampak yang dibaca untuk --changed/--since (default: .forktest/map.json)
      --explain         bersama --changed/--since: cetak alasan tiap file test dipilih
      --fast            satu proses per file, bukan satu per test (lihat di atas)
      --preload         muat kelas PHPUnit/Mockery sekali di induk sebelum fork
      --no-opcache      jangan aktifkan opcache untuk run ini
      --bootstrap FILE  file bootstrap (default: "bootstrap" dari phpunit.xml, kalau tidak ada vendor/autoload.php)
      --list            tampilkan test yang ditemukan lalu keluar
  -v, --verbose         log lengkap: pesan penuh dan stack trace test yang gagal, ditambah daftar test
                        skipped, incomplete, dan risky
  -h, --help            tampilkan bantuan
      --version         tampilkan versi
```

Kode keluar: `0` kalau tidak ada yang gagal atau error (test skipped dan incomplete tidak dihitung), `1` selain itu, `2`
untuk kesalahan penggunaan.

`--filter` adalah regular expression PHP tanpa anchor yang dicocokkan dengan nama test seperti yang dicetak PHPUnit
(`Namespace\Class::method with data set #0`). Contoh: `--filter TransferOwnership`, `--filter '::testRejects'`.

`--preload` memberi hasil identik di benchmark tapi tidak membuat run lebih cepat secara berarti setelah opcache
menyala, jadi dimatikan secara default.

## Impact selection: jalankan hanya test yang bisa terdampak perubahanmu

Kebanyakan perubahan hanya menyentuh beberapa file, jadi kebanyakan test tidak mungkin terdampak. forktest bisa
mencari tahu yang mana.

```bash
vendor/bin/forktest --record-map .forktest/map.json   # sekali, dan ulangi setelah merge besar (full run)
vendor/bin/forktest --changed                         # test terdampak sejak merge-base dengan master/main
vendor/bin/forktest --since origin/develop            # ... atau terhadap ref git apa pun
vendor/bin/forktest --changed --explain               # sekaligus cetak alasan tiap file test dipilih
```

Tambahkan `.forktest/` ke `.gitignore`. `--changed`/`--since` membaca peta dari `.forktest/map.json` kecuali kamu
memberi `--map FILE`.

Cara kerja. Setiap test sudah berjalan di proses sendiri, jadi setelah test selesai forktest bertanya ke PHP file
project mana saja yang dimuat proses itu (`get_included_files()`, vendor dikecualikan). Itulah peta dependensinya:
file project ke file test yang memuatnya. Tidak butuh driver coverage dan biaya merekamnya tidak terasa. `--changed`
lalu mengambil `git diff` terhadap base (file yang di-commit, staged, unstaged, dan untracked) dan memilih:

- file test yang memuat file yang berubah, dan file test yang berubah sendiri;
- file test yang tidak ada di peta (test baru), selalu;
- untuk file PHP berubah yang belum pernah dilihat peta, file test yang menyebut nama class-nya;
- file test yang membaca file project dari disk (`file_get_contents`, `glob`, `getFileName()`, ...), kalau file yang
  berubah disebut di source-nya, karena peta berbasis include tidak bisa melihat pembacaan itu;
- **semuanya**, kalau `composer.json`/`composer.lock`, `phpunit.xml(.dist)`, `tests/bootstrap.php`, `.env*`, atau file
  yang dimuat bootstrap berubah.

Perubahan non-PHP (dokumen, aset) tidak memilih apa pun; kalau tidak ada yang terdampak, forktest mengatakannya dan
keluar dengan kode `0`. Pilihan dicetak ke stderr, termasuk berapa commit peta tertinggal dari `HEAD`.

Diukur pada suite 6.954 test (PHP 7.3, 4 core):

| Apa                                                          | Hasil                                               |
|--------------------------------------------------------------|-----------------------------------------------------|
| Merekam peta saat full run                                   | 49,0 detik vs 48,5 detik tanpa rekam; 82 KB untuk 331 file test / 766 file project |
| Merekam dua kali                                             | peta identik (0 dari 331 file test yang berbeda)    |
| Ukuran peta yang umum                                        | satu file test memuat median 6 file project (maksimum 75); hanya 388 dari 1.533 file `app/` yang dimuat test unit mana pun |
| Branch nyata (23 file berubah)                               | 32 dari 331 file test, 509 dari 6.954 test: **4,6 detik** vs 48,5 detik |
| 509 test yang sama, dibandingkan dengan full run             | status setiap test identik                          |
| Cek keamanan: 7 file project sengaja dirusak, suite penuh dijalankan tiap kali | 0 file test terdampak yang terlewat (lihat di bawah) |

Cek keamanannya menyalin repository, menambahkan `throw` di akhir file yang dimuat test (1 sampai 91 file test
memuatnya), menjalankan seluruh suite, lalu membandingkannya dengan run tanpa modifikasi. Setiap test yang hasilnya
berubah, termasuk test yang hilang karena file-nya tidak lagi bisa dimuat, ada di dalam pilihan. Pilihan bersifat
superset: untuk file yang dimuat 91 file test, 54 file test berubah hasilnya dan keseluruhan 91 terpilih.

Yang tidak bisa dilihat: apa pun yang bukan file PHP yang dimuat lewat `include`/autoload saat perekaman, seperti
data dari database, nilai `.env`, file JSON/YAML yang dibaca kode yang dites, atau jalur kode yang hanya dilewati
test pada sebagian run. Heuristik pembaca file menutup sebagian, bukan semuanya. Cek keamanan di atas merusak file saat
dimuat, jadi ia memvalidasi hubungan include, bukan perilaku setiap jalur kode.

Perlakukan `--changed` sebagai siklus edit-lalu-jalankan yang cepat, dan tetap jalankan full run untuk CI dan sebelum
merge. Rekam ulang peta setelah merge besar atau ketika `--changed` melaporkan peta tertinggal banyak commit: test yang
mulai memuat file baru hanya ditemukan lewat file yang berubah, bukan lewat file barunya sendiri, sampai peta
diperbarui.

## Logging

Output default sengaja ringkas, karena fokus forktest adalah kecepatan: satu huruf per test
(`.` lolos, `E` error, `F` failure, `W` warning, `S` skipped, `I` incomplete, `R` risky), lalu tiap test yang gagal
dengan dua baris pertama pesannya, dan satu baris ringkasan. Semua yang di bawah ini bersifat opsional.

- `-v` mencetak pesan lengkap dan stack trace (sudah difilter) tiap test yang gagal, serta mendaftar test skipped,
  incomplete, dan risky beserta pesannya.
- `--log-junit FILE` menulis laporan JUnit XML (`testsuites > testsuite` per class `> testcase`, dengan elemen
  `failure`, `error`, dan `skipped`, serta atribut `classname`, `file`, `time`, dan `assertions`). Warning ditulis
  sebagai `error`, test incomplete sebagai `skipped`, dan test risky sebagai lolos, sehingga totalnya sama dengan
  baris ringkasan.
- `--stop-on-failure` berhenti di error atau failure pertama dan menyebutkan berapa test yang tidak dijalankan.
  Test yang sedang berjalan dihentikan.

Biaya pada suite 6.954 test (run tunggal): default 48,5 detik, `-v` 49,1 detik, `--log-junit` 51,9 detik (laporan
3 MB). Stack trace hanya dibangun saat `-v` atau `--log-junit` dipakai, jadi run default mengerjakan hal yang sama
seperti sebelumnya.

## Perbedaan yang diketahui: opcache dan diagnostik compile-time

Dengan opcache menyala (default), warning atau deprecation compile-time, misalnya
"Unparenthesized `a ? b : c ? d : e` is deprecated" dari PHP 7.4, tidak dimunculkan di dalam test. Pesannya dicetak
mentah ke stderr dan PHPUnit tidak mengubahnya jadi error test. Tanpa opcache, PHPUnit mengubahnya jadi error, sehingga
test yang gagal di PHPUnit murni atau ParaTest bisa lolos di forktest.

Pada suite 6.954 test, ini tidak mengubah apa pun di PHP 7.3 dan tepat satu test di PHP 7.4 (selebihnya full run
cocok dengan ParaTest). Kalau kamu bergantung pada diagnostik seperti itu, misalnya saat upgrade PHP, atau di CI,
jalankan dengan `--no-opcache`. Biayanya sekitar 2,4x (118 detik, bukan 48 detik di suite di atas) dan perilakunya
kembali seperti biasa.

## Yang belum didukung

- Tidak ada code coverage, tidak ada logging TestDox/JSON, tidak ada urutan acak. (JUnit XML, `--group`, dan
  `--exclude-group` didukung.)
- Tidak ada `@depends`. Setiap test berjalan di prosesnya sendiri, jadi test yang bergantung pada hasil test lain tidak
  didukung. Suite tempat ia dikembangkan tidak punya satu pun; ini belum diuji.
- Dari `phpunit.xml` hanya `bootstrap`, `stopOnFailure`, bagian `<php>`, dan entri `<directory>`/`<file>` testsuite
  (dengan `suffix`) yang dibaca. Pengaturan seperti `processIsolation`, `backupGlobals`, `<exclude>`, `<listeners>`,
  dan `<filter>` diabaikan.
- `setUpBeforeClass` dan `tearDownAfterClass` berjalan sekali per test, bukan sekali per class, di kedua mode.
- Impact selection hanya tahu apa yang dimuat test lewat `include`/autoload PHP saat peta direkam (lihat di atas).
- Output yang dicetak test dibuang. Test yang gagal menampilkan dua baris pertama pesannya kecuali kamu memakai `-v`.
- Test yang tidak menghasilkan hasil selama 120 detik (ubah dengan `--timeout`) dihentikan dan dilaporkan sebagai
  error.

## Lisensi

MIT, lihat [LICENSE](LICENSE). Daftar perubahan ada di [CHANGELOG.md](CHANGELOG.md).

## Pengembangan

```bash
composer install
composer selftest            # atau: bash scripts/selftest.sh [path/ke/vendor/autoload.php]
```

`scripts/selftest.sh` menjalankan `tests/fixtures/ControlTest.php`, file berisi test yang sengaja dirusak (assertion
gagal, exception, ekspektasi Mockery yang tidak terpenuhi, notice PHP, fatal error, skipped, incomplete, data
provider, kebocoran state), lalu memeriksa bahwa forktest melaporkan total yang sama dengan PHPUnit (13 test,
8 assertion, 4 error, 2 failure, 1 skipped, 1 incomplete). Ia juga memeriksa `--filter`, `--group`,
`--exclude-group`, `--stop-on-failure`, `--log-junit` (XML valid, total sama), `--timeout` (memakai
`tests/fixtures/SlowTest.php`), dan impact selection (`--record-map`, `--changed`, di repository git sementara). Jangan masukkan `tests/fixtures` ke testsuite `phpunit.xml`.

Saat mengubah runner, bandingkan dengan PHPUnit atau ParaTest di suite nyata sebelum percaya pada peningkatan
kecepatan: run yang lebih cepat baru berarti kalau total dan daftar test yang gagal tidak berubah. Dua bug yang
ketemu dengan cara itu sejauh ini adalah induk yang memuat kelas aplikasi saat discovery (error Mockery "class already
exists") dan `--list` yang menjalankan test di mode `--fast`.
