import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/auth/forgot_password_view.dart';

void main() {
  group('ResetPasswordArgs.tryParse', () {
    test('parses a map carrying email + token (deep-link query params)', () {
      final args = ResetPasswordArgs.tryParse({
        'email': 'you@example.com',
        'token': 'abc123',
      });

      expect(args, isNotNull);
      expect(args!.email, 'you@example.com');
      expect(args.token, 'abc123');
    });

    test('returns null when either field is missing', () {
      expect(ResetPasswordArgs.tryParse({'email': 'you@example.com'}), isNull);
      expect(ResetPasswordArgs.tryParse({'token': 'abc123'}), isNull);
      expect(ResetPasswordArgs.tryParse(const {}), isNull);
    });

    test('passes an existing args instance straight through', () {
      const original = ResetPasswordArgs(email: 'a@b.com', token: 'tok');
      expect(ResetPasswordArgs.tryParse(original), same(original));
    });

    test('ignores unrelated argument types', () {
      expect(ResetPasswordArgs.tryParse('just-a-string'), isNull);
      expect(ResetPasswordArgs.tryParse(null), isNull);
    });
  });
}
