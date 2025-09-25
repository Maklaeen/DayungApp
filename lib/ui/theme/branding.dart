import 'package:flutter/material.dart';

// Core palette (already used in Secretary)
const Color kPrimary = Color(0xFF0D47A1);
const Color kPrimaryDark = Color(0xFF083366);
const Color kAccent = Color(0xFF2E7D32);
const Color kWarn = Color(0xFFF57C00);
const Color kDanger = Color(0xFFC62828);
const Color kNeutralText = Color(0xFF1F2937);
const Color kSubtleText = Color(0xFF4B5563);
const Color kBg = Color(0xFFFAFAF7);

TextStyle kHeaderTitleStyle(double size) => TextStyle(
  fontSize: size,
  fontWeight: FontWeight.w800,
  fontFamily: 'Montserrat',
  letterSpacing: .4,
  height: 1.15,
  color: kPrimaryDark,
);

const TextStyle kHeaderSubStyle = TextStyle(
  fontSize: 13,
  fontFamily: 'OpenSans',
  color: kSubtleText,
  height: 1.1,
);