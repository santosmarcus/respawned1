import 'package:flutter/services.dart';

class AppValidators {
  AppValidators._();

  //Letters (incl. accented), spaces, hyphens, apostrophes, and periods
  //(for initials like "J.R."). No digits, no symbols.
  static final RegExp _namePattern =
  RegExp(r"^[A-Za-zÀ-ÖØ-öø-ÿ' \-.]+$");

  // Root cause of the "sample@school.edu.ph is invalid" bug: the previous
  // pattern only allowed a single dot in the domain (one label + one TLD),
  // so any multi-label domain (.edu.ph, .co.uk) or subdomain was rejected
  // outright even though it's a syntactically valid address. This pattern
  // allows the local part to include plus-addressing (name+tag@...) and
  // the domain to have any number of dot-separated labels.
  static final RegExp _emailPattern =
  RegExp(r'^[\w.+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$');

  // Philippine mobile number, 10 digits starting with 9
  static final RegExp _phPhoneLocalPattern = RegExp(r'^9\d{9}$');

  // accepts (+63)
  static final RegExp _phPhoneFlexiblePattern =
  RegExp(r'^(\+?63|0)?9\d{9}$');

  static String? required(String? value, {String fieldName = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required.';
    }
    return null;
  }

  // A person's name: required, letters only, sensible length.
  static String? name(
      String? value, {
        String fieldName = 'Name',
        bool required = true,
      }) {
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      return required ? '$fieldName is required.' : null;
    }
    if (v.length < 2) return '$fieldName is too short.';
    if (v.length > 60) return '$fieldName is too long.';
    if (!_namePattern.hasMatch(v)) {
      return '$fieldName can only contain letters.';
    }
    return null;
  }

  static String? email(String? value, {bool required = true}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      return required ? 'Email is required.' : null;
    }
    if (!_emailPattern.hasMatch(v)) {
      return 'Invalid email format.';
    }
    return null;
  }

  static String? phLocalPhone(String? value, {bool required = true}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      return required ? 'Mobile number is required.' : null;
    }
    if (!_phPhoneLocalPattern.hasMatch(v)) {
      return 'Enter a valid 10-digit mobile number starting with 9.';
    }
    return null;
  }

  // For a field that captures a full number the person might type with a leading 0 / +63 themselves
  static String? phFlexiblePhone(String? value, {bool required = true}) {
    final v = (value ?? '').trim().replaceAll(RegExp(r'[\s-]'), '');
    if (v.isEmpty) {
      return required ? 'Mobile number is required.' : null;
    }
    if (!_phPhoneFlexiblePattern.hasMatch(v)) {
      return 'Please enter a valid Philippine mobile number.';
    }
    return null;
  }

  static String? password(String? value, {int minLength = 8}) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required.';
    if (v.length < minLength) {
      return 'Password must be at least $minLength characters long.';
    }
    return null;
  }

  // A positive monetary amount. Accepts "500", "500.00" — rejects letters, negatives, and "0"/"".
  static String? amount(
      String? value, {
        String fieldName = 'Amount',
        double min = 0.01,
        double? max,
      }) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return '$fieldName is required.';
    final parsed = double.tryParse(v);
    if (parsed == null) return 'Enter a valid amount.';
    if (parsed < min) return '$fieldName must be greater than 0.';
    if (max != null && parsed > max) {
      return '$fieldName must be $max or less.';
    }
    return null;
  }

  // A plain positive whole number (e.g. quantity, headcount).
  static String? wholeNumber(
      String? value, {
        String fieldName = 'This field',
        bool required = true,
        int min = 0,
      }) {
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      return required ? '$fieldName is required.' : null;
    }
    final parsed = int.tryParse(v);
    if (parsed == null) return '$fieldName must be a whole number.';
    if (parsed < min) return '$fieldName must be at least $min.';
    return null;
  }

  // Free-text field (address, description, etc.)
  static String? nonEmptyText(
      String? value, {
        String fieldName = 'This field',
        int minLength = 1,
      }) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return '$fieldName is required.';
    if (v.length < minLength) {
      return '$fieldName must be at least $minLength characters.';
    }
    return null;
  }

  static final RegExp _licensePlatePattern = RegExp(r'^[A-Za-z0-9]{2,4}[\s-]?[0-9]{2,5}$');

  // A Philippine vehicle plate (letters+digits, e.g. "ABC 1234" or "ABC1234")
  static String? licensePlate(String? value, {bool required = true}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      return required ? 'License plate number is required.' : null;
    }
    if (!_licensePlatePattern.hasMatch(v)) {
      return 'Enter a valid plate number (e.g. ABC 1234).';
    }
    return null;
  }
}

class AppInputFormatters {
  AppInputFormatters._();

  // Blocks anything that isn't a letter, space, hyphen, apostrophe, or
  // period — use on any name field.
  static final TextInputFormatter nameOnly = FilteringTextInputFormatter.allow(
    RegExp(r"[A-Za-zÀ-ÖØ-öø-ÿ' \-.]"),
  );

  // Digits only
  static final TextInputFormatter digitsOnly =
      FilteringTextInputFormatter.digitsOnly;

  // Digits only, capped at [length] characters — for a fixed-width local
  // phone number field (this app's "+63" fields are always 10 digits).
  static List<TextInputFormatter> digitsWithMaxLength(int length) => [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(length),
  ];

  // Digits plus an optional leading "+" — for a phone field with no fixed
  // prefix chip, where the person types the whole number themselves (e.g.
  // "09171234567" or "+639171234567").
  static final List<TextInputFormatter> phoneFlexible = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
    LengthLimitingTextInputFormatter(13),
  ];

  // Digits with up to 2 decimal places — money amounts. Blocks a second
  // decimal point and more than 2 digits after it, but still lets the
  // person type "12" before adding ".50".
  static final TextInputFormatter decimal = TextInputFormatter.withFunction(
        (oldValue, newValue) {
      if (newValue.text.isEmpty) return newValue;
      if (RegExp(r'^\d*\.?\d{0,2}$').hasMatch(newValue.text)) {
        return newValue;
      }
      return oldValue;
    },
  );

  // Letters, digits, spaces, and hyphens — vehicle plate numbers.
  static final TextInputFormatter alphanumericWithSpaces =
  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\s\-]'));
}