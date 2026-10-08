-- =====================================================================
-- Analisis Donasi Zakat Ramadan 1446H - BerbagiRamadan
-- Tabel yang dipakai: donatur, donasi, kategori_donasi, penerima, distribusi
-- Catatan: butuh DBMS yang mendukung CTE dan window function
--          (MySQL 8+, PostgreSQL, SQLite 3.25+).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Gambaran umum donasi
-- Pertanyaan: berapa donatur, transaksi, dan total donasi?
-- Perbaikan: pakai donatur_id (bukan nama) agar donatur dengan nama
-- sama tidak terhitung satu; JOIN tidak diperlukan.
-- ---------------------------------------------------------------------
SELECT
    COUNT(DISTINCT donatur_id) AS total_donatur,
    COUNT(id)                  AS total_transaksi,
    SUM(jumlah)                AS total_donasi
FROM donasi;


-- ---------------------------------------------------------------------
-- 2. Donasi per kategori
-- Pertanyaan: kategori mana yang kontribusinya terbesar?
-- ---------------------------------------------------------------------
SELECT
    kd.nama_kategori,
    COUNT(d.id)   AS jumlah_transaksi,
    SUM(d.jumlah) AS total_donasi
FROM donasi d
JOIN kategori_donasi kd ON d.kategori_id = kd.id
GROUP BY kd.nama_kategori
ORDER BY total_donasi DESC;


-- ---------------------------------------------------------------------
-- 3. Segmentasi donatur berdasarkan tier
-- Aturan: Platinum >= 5.000.000 | Gold >= 2.000.000
--         Silver >= 500.000     | Bronze < 500.000
-- ---------------------------------------------------------------------
WITH total_per_donatur AS (
    SELECT
        donatur_id,
        SUM(jumlah) AS total_donasi
    FROM donasi
    GROUP BY donatur_id
)
SELECT
    dn.nama,
    dn.kota,
    t.total_donasi,
    CASE
        WHEN t.total_donasi >= 5000000 THEN 'Platinum'
        WHEN t.total_donasi >= 2000000 THEN 'Gold'
        WHEN t.total_donasi >= 500000  THEN 'Silver'
        ELSE 'Bronze'
    END AS tier
FROM total_per_donatur t
JOIN donatur dn ON t.donatur_id = dn.id
ORDER BY t.total_donasi DESC;


-- ---------------------------------------------------------------------
-- 4. Ranking donatur per kota
-- DENSE_RANK dipakai agar donatur dengan total sama mendapat ranking sama.
-- (CTE tidak lagi menghitung tier karena tidak dipakai di sini.)
-- ---------------------------------------------------------------------
WITH total_per_donatur AS (
    SELECT
        donatur_id,
        SUM(jumlah) AS total_donasi
    FROM donasi
    GROUP BY donatur_id
)
SELECT
    dn.nama,
    dn.kota,
    t.total_donasi,
    DENSE_RANK() OVER (PARTITION BY dn.kota ORDER BY t.total_donasi DESC) AS ranking_kota
FROM total_per_donatur t
JOIN donatur dn ON t.donatur_id = dn.id
ORDER BY dn.kota ASC, t.total_donasi DESC;


-- ---------------------------------------------------------------------
-- 5. Tren donasi harian dan running total
-- ---------------------------------------------------------------------
WITH donasi_per_hari AS (
    SELECT
        tanggal,
        SUM(jumlah) AS total_per_hari
    FROM donasi
    GROUP BY tanggal
)
SELECT
    tanggal,
    total_per_hari                                   AS donasi_harian,
    SUM(total_per_hari) OVER (ORDER BY tanggal ASC)  AS kumulatif
FROM donasi_per_hari
ORDER BY tanggal ASC;


-- ---------------------------------------------------------------------
-- 6. 10 hari terakhir vs sebelumnya (Ramadan 1446H: 1-30 Maret 2025)
-- Sebelumnya = 20 hari, 10 Hari Terakhir = 10 hari.
-- Perbaikan: ditambah transaksi_per_hari dan donasi_per_hari karena
-- panjang kedua periode berbeda, sehingga total mentah tidak adil
-- untuk dibandingkan.
-- Asumsi: tanggal di luar 21 Maret ke atas dianggap 'Sebelumnya'.
-- ---------------------------------------------------------------------
WITH donasi_periode AS (
    SELECT
        id,
        jumlah,
        CASE WHEN tanggal >= '2025-03-21' THEN '10 Hari Terakhir' ELSE 'Sebelumnya' END AS periode,
        CASE WHEN tanggal >= '2025-03-21' THEN 10 ELSE 20 END                          AS jumlah_hari
    FROM donasi
)
SELECT
    periode,
    COUNT(id)                                    AS jumlah_transaksi,
    SUM(jumlah)                                  AS total_donasi,
    ROUND(AVG(jumlah))                           AS rata_rata_donasi,
    ROUND(COUNT(id) * 1.0 / MAX(jumlah_hari), 2) AS transaksi_per_hari,
    ROUND(SUM(jumlah) * 1.0 / MAX(jumlah_hari))  AS donasi_per_hari
FROM donasi_periode
GROUP BY periode;


-- ---------------------------------------------------------------------
-- 7. Distribusi dana per kategori mustahik
-- ---------------------------------------------------------------------
SELECT
    pen.kategori_mustahik,
    COUNT(dis.id)   AS jumlah_penyaluran,
    SUM(dis.jumlah) AS total_disalurkan
FROM distribusi dis
JOIN penerima pen ON dis.penerima_id = pen.id
GROUP BY pen.kategori_mustahik
ORDER BY total_disalurkan DESC;


-- ---------------------------------------------------------------------
-- 8. Efisiensi penyaluran donasi
-- Perbaikan: operator perkalian (*) ditulis jelas; CTE disederhanakan.
-- Catatan: tabel distribusi tidak punya relasi ke donasi, jadi
-- efisiensi dihitung di level total, bukan per donasi.
-- ---------------------------------------------------------------------
WITH total_distribusi AS (
    SELECT SUM(jumlah) AS total_distribusi FROM distribusi
),
total_donasi AS (
    SELECT SUM(jumlah) AS total_donasi FROM donasi
)
SELECT
    td.total_donasi,
    tx.total_distribusi,
    ROUND(tx.total_distribusi * 100.0 / td.total_donasi, 2) AS persentase_tersalurkan
FROM total_distribusi tx
CROSS JOIN total_donasi td;


-- ---------------------------------------------------------------------
-- 9. Gap analysis: rata-rata penyaluran per penerima
-- LEFT JOIN agar penerima yang belum pernah menerima dana tetap terhitung.
-- Hati-hati membaca hasilnya: beberapa kategori hanya punya 1 penerima.
-- ---------------------------------------------------------------------
SELECT
    pen.kategori_mustahik,
    COUNT(DISTINCT pen.id)                                          AS jumlah_penerima,
    COALESCE(SUM(dis.jumlah), 0)                                    AS total_disalurkan,
    ROUND(COALESCE(SUM(dis.jumlah), 0) * 1.0 / COUNT(DISTINCT pen.id)) AS rata_rata_per_penerima
FROM penerima pen
LEFT JOIN distribusi dis ON pen.id = dis.penerima_id
GROUP BY pen.kategori_mustahik
ORDER BY rata_rata_per_penerima ASC;


-- ---------------------------------------------------------------------
-- 10. Laporan eksekutif: kontribusi tiap kategori donasi
-- Klasifikasi: Utama >= 30% | Signifikan >= 15% | Pendukung < 15%
-- Perbaikan: kolom ditulis eksplisit (bukan SELECT *), persentase
-- dihitung sekali di CTE kedua agar CASE tidak mengulang rumus.
-- ---------------------------------------------------------------------
WITH per_kategori AS (
    SELECT
        kd.nama_kategori,
        COUNT(d.id)   AS jumlah_transaksi,
        SUM(d.jumlah) AS total_donasi
    FROM donasi d
    JOIN kategori_donasi kd ON d.kategori_id = kd.id
    GROUP BY kd.nama_kategori
),
dengan_persen AS (
    SELECT
        nama_kategori,
        jumlah_transaksi,
        total_donasi,
        ROUND(total_donasi * 100.0 / SUM(total_donasi) OVER (), 2) AS persentase_kontribusi
    FROM per_kategori
)
SELECT
    nama_kategori,
    jumlah_transaksi,
    total_donasi,
    persentase_kontribusi,
    CASE
        WHEN persentase_kontribusi >= 30 THEN 'Utama'
        WHEN persentase_kontribusi >= 15 THEN 'Signifikan'
        ELSE 'Pendukung'
    END AS klasifikasi
FROM dengan_persen
ORDER BY total_donasi DESC;
