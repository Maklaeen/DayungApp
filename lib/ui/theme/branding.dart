import 'package:flutter/material.dart';

const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kInfo = kPrimary;
const Color kSuccess = kAccent;
const Color kWarn = Color(0xFFF57C00);
const Color kWarningText = Color(0xFF8A4B08);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);
const Color kBg = Color(0xFFFAFAF7);
const Color kSurface = Color(0xFFFFFFFF);
const Color kSoftSurface = Color(0xFFF8FAFC);
const Color kBorder = Color(0xFFD6DCE8);
const Color kDarkBackground = Color(0xFF0F172A);
const Color kDarkSurface = Color(0xFF162033);
const Color kDarkSoftSurface = Color(0xFF1B2435);
const Color kDarkBorder = Color(0xFF475569);

TextStyle kHeaderTitleStyle(double size) => TextStyle(
  fontSize: size,
  fontWeight: FontWeight.w800,
  letterSpacing: .4,
  height: 1.15,
  color: kPrimaryDark,
);

const TextStyle kHeaderSubStyle = TextStyle(
  fontSize: 13,
  color: kSubtleText,
  height: 1.1,
);
