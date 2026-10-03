import 'dart:async';

import 'package:flutter_contacts/flutter_contacts.dart' as fc;

import '../../core/models/contact.dart';
import '../../core/permissions/permission_service.dart';

/// Reads the device address book.
///
/// Used only by the optional "Sync contact to phone" switch and the local
/// contact picker. When permission is unavailable the app falls back to its own
/// locally stored contacts, so nothing breaks.
class DeviceContactService {
  const DeviceContactService({this.permissions = const PermissionService()});

  final PermissionService permissions;

  Future<bool> isAvailable() async {
    try {
      return await fc.FlutterContacts.requestPermission(readonly: true);
    } on Exception {
      return false;
    }
  }

  /// Reads up to [limit] device contacts, mapped to the app's [Contact] model.
  ///
  /// Returns an empty list when access is denied — the caller decides whether
  /// to show an explanatory message.
  Future<List<Contact>> read({int limit = 500}) async {
    try {
      final PermissionResult result =
          await permissions.request(AppPermission.contacts);
      if (!result.isGranted) return <Contact>[];

      final List<fc.Contact> contacts = await fc.FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );

      final List<Contact> mapped = <Contact>[];
      for (final fc.Contact c in contacts.take(limit)) {
        final String display = c.displayName.trim();
        if (display.isEmpty) continue;
        final List<String> parts = display.split(RegExp(r'\s+'));
        final String first = parts.first;
        final String last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        final String? phone =
            c.phones.isNotEmpty ? c.phones.first.number : null;
        mapped.add(
          Contact(
            id: 'device_${c.id}',
            firstName: first,
            lastName: last,
            phone: phone ?? '',
            isSyncedToDevice: true,
          ),
        );
      }
      mapped.sort((a, b) => a.sortedKey.compareTo(b.sortedKey));
      return mapped;
    } on Exception {
      return <Contact>[];
    }
  }

  /// Writes a contact to the device address book.
  ///
  /// Returns false when permission is missing or the platform call fails.
  Future<bool> writeToDevice({
    required String firstName,
    String lastName = '',
    String? phone,
  }) async {
    try {
      final PermissionResult result =
          await permissions.request(AppPermission.contacts);
      if (!result.isGranted) return false;

      final fc.Contact contact = fc.Contact(
        name: fc.Name(first: firstName, last: lastName),
      );
      if (phone != null && phone.trim().isNotEmpty) {
        contact.phones = <fc.Phone>[fc.Phone(phone.trim())];
      }
      await fc.FlutterContacts.insertContact(contact);
      return true;
    } on Exception {
      return false;
    }
  }
}
