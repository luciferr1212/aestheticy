import '../file_association_service.dart';

/// Windows implementation placeholder for [FileAssociationService].
///
/// Full Windows shell registration is scheduled for Phase 5 (open-with &
/// single-instance). Until then this returns `false` without mutating the
/// Windows registry.
class WindowsFileAssociationService implements FileAssociationService {
  @override
  bool get isSupported => false;

  @override
  Future<bool> isRegistered(String extension) async => false;

  @override
  Future<bool> registerExtensions(List<String> extensions) async => false;
}
