enum DownloadSource {
  official('Official', 'Mojang official servers'),
  china('China (BMCLAPI)', 'Mirror for mainland China');

  const DownloadSource(this.label, this.description);

  final String label;
  final String description;

  static DownloadSource fromName(String? name) =>
      DownloadSource.values.firstWhere(
        (e) => e.name == name,
        orElse: () => DownloadSource.official,
      );
}
