import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart'
    show
        LinearProgressIndicator; // Use Material LinearProgressIndicator for simplicity
import 'dart:math';

double log10(num x) => log(x) / ln10;

void main() {
  runApp(const FfmiCalculatorApp());
}

// --- Enums ---
enum Gender { male, female }

enum WeightUnit { kg, lbs }

enum HeightUnit { cm, ftIn }

// --- Constants ---
class FfmiRanges {
  // Ranges can vary slightly based on source, these are common guidelines
  static const Map<Gender, Map<String, double>> ranges = {
    Gender.male: {
      'Below Average': 18.0,
      'Average': 20.0,
      'Above Average': 22.0,
      'Muscular': 25.0,
      'Very Muscular': double.infinity, // Upper bound for the last range
    },
    Gender.female: {
      'Below Average': 14.0,
      'Average': 16.0,
      'Above Average': 18.0,
      'Muscular': 21.0,
      'Very Muscular': double.infinity,
    },
  };

  static const Map<Gender, List<String>> labels = {
    Gender.male: ['< 18', '18-20', '20-22', '22-25', '> 25'],
    Gender.female: ['< 14', '14-16', '16-18', '18-21', '> 21'],
  };

  static const Map<Gender, List<double>> thresholds = {
    Gender.male: [0, 18.0, 20.0, 22.0, 25.0],
    Gender.female: [0, 14.0, 16.0, 18.0, 21.0],
  };

  static String getInterpretation(double ffmi, Gender gender) {
    final genderRanges = ranges[gender]!;
    if (ffmi < genderRanges['Below Average']!) return 'Below Average';
    if (ffmi < genderRanges['Average']!) return 'Average';
    if (ffmi < genderRanges['Above Average']!) return 'Above Average';
    if (ffmi < genderRanges['Muscular']!) return 'Muscular';
    return 'Very Muscular / Potentially Enhanced';
  }

  static int getRangeIndex(double ffmi, Gender gender) {
    final thresholdsList = thresholds[gender]!;
    for (int i = thresholdsList.length - 1; i >= 0; i--) {
      if (ffmi >= thresholdsList[i]) {
        return i;
      }
    }
    return 0; // Should not happen if ffmi is non-negative
  }
}

class FfmiCalculatorApp extends StatelessWidget {
  const FfmiCalculatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      title: 'FFMI Calculator',
      theme: CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: CupertinoColors.systemBlue,
      ),
      home: FfmiCalculatorScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class FfmiCalculatorScreen extends StatefulWidget {
  const FfmiCalculatorScreen({super.key});

  @override
  State<FfmiCalculatorScreen> createState() => _FfmiCalculatorScreenState();
}

class _FfmiCalculatorScreenState extends State<FfmiCalculatorScreen> {
  // --- Input Controllers ---
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightCmController = TextEditingController();
  final TextEditingController _heightFtController = TextEditingController();
  final TextEditingController _heightInController = TextEditingController();
  final TextEditingController _bodyFatController = TextEditingController();
  final TextEditingController _ffmiGoalController = TextEditingController();

  // --- State Variables ---
  Gender _selectedGender = Gender.male;
  WeightUnit _selectedWeightUnit = WeightUnit.kg;
  HeightUnit _selectedHeightUnit = HeightUnit.cm;

  double? _ffmiResult;
  double? _adjustedFfmiResult;
  double? _lbmResult;
  String? _interpretation;
  double? _ffmiGoal;

  // --- Body Fat Estimator State ---
  final TextEditingController _neckController = TextEditingController();
  final TextEditingController _waistController = TextEditingController();
  final TextEditingController _hipController =
      TextEditingController(); // Only for female
  bool _useBfpEstimator = false;
  HeightUnit _bfpHeightUnit =
      HeightUnit.cm; // Use separate unit state if needed or sync
  // Assume measurements in cm for BFP estimation for simplicity here
  // Add unit conversion later if needed for BFP inputs

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // --- Helper Functions ---
  Future<void> _saveUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('weight', _weightController.text);
    await prefs.setString('heightCm', _heightCmController.text);
    await prefs.setString('heightFt', _heightFtController.text);
    await prefs.setString('heightIn', _heightInController.text);
    await prefs.setString('bodyFat', _bodyFatController.text);
    await prefs.setString('ffmiGoal', _ffmiGoalController.text);
    await prefs.setInt('gender', _selectedGender.index);
    await prefs.setInt('weightUnit', _selectedWeightUnit.index);
    await prefs.setInt('heightUnit', _selectedHeightUnit.index);
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _weightController.text = prefs.getString('weight') ?? '';
      _heightCmController.text = prefs.getString('heightCm') ?? '';
      _heightFtController.text = prefs.getString('heightFt') ?? '';
      _heightInController.text = prefs.getString('heightIn') ?? '';
      _bodyFatController.text = prefs.getString('bodyFat') ?? '';
      _ffmiGoalController.text = prefs.getString('ffmiGoal') ?? '';
      _selectedGender = Gender.values[prefs.getInt('gender') ?? 0];
      _selectedWeightUnit = WeightUnit.values[prefs.getInt('weightUnit') ?? 0];
      _selectedHeightUnit = HeightUnit.values[prefs.getInt('heightUnit') ?? 0];
    });
  }

  double _getWeightInKg() {
    final weight = double.tryParse(_weightController.text) ?? 0.0;
    return _selectedWeightUnit == WeightUnit.kg
        ? weight
        : weight * 0.453592; // lbs to kg
  }

  double _getHeightInCm() {
    if (_selectedHeightUnit == HeightUnit.cm) {
      return double.tryParse(_heightCmController.text) ?? 0.0;
    } else {
      final feet = double.tryParse(_heightFtController.text) ?? 0.0;
      final inches = double.tryParse(_heightInController.text) ?? 0.0;
      return (feet * 30.48) + (inches * 2.54); // ft/in to cm
    }
  }

  double _getHeightInM() {
    return _getHeightInCm() / 100.0;
  }

  void _calculateAndSetBfp() {
    final double neckCm = double.tryParse(_neckController.text.trim()) ?? 0.0;
    final double waistCm = double.tryParse(_waistController.text.trim()) ?? 0.0;
    final double heightCm = _getHeightInCm(); // in cm

    if (neckCm <= 0 || waistCm <= 0 || heightCm <= 0) {
      _showErrorDialog(
        "Please enter valid neck, waist, and height measurements.",
      );
      return;
    }

    double estimatedBfp;

    try {
      if (_selectedGender == Gender.male) {
        // —— SI (metric) US Navy formula for Men ——
        // BFP = 495
        //       ————————————————————————————————  − 450
        //       (1.0324 − 0.19077·log10(waist−neck)
        //               + 0.15456·log10(height))
        //
        if (waistCm <= neckCm) {
          throw ArgumentError("Waist must be greater than neck.");
        }
        final double A =
            1.0324 -
            0.19077 * log10(waistCm - neckCm) +
            0.15456 * log10(heightCm);
        estimatedBfp = 495.0 / A - 450.0;
      } else {
        // —— SI (metric) US Navy formula for Women ——
        // BFP = 495
        //       ——————————————————————————————————  − 450
        //       (1.29579 − 0.35004·log10(waist+hip−neck)
        //               + 0.22100·log10(height))
        //
        final double hipCm = double.tryParse(_hipController.text.trim()) ?? 0.0;
        if (hipCm <= 0) {
          _showErrorDialog("Please enter valid hip measurement for females.");
          return;
        }
        if ((waistCm + hipCm) <= neckCm) {
          throw ArgumentError("Waist + Hip must be greater than neck.");
        }
        final double B =
            1.29579 -
            0.35004 * log10(waistCm + hipCm - neckCm) +
            0.22100 * log10(heightCm);
        estimatedBfp = 495.0 / B - 450.0;
      }

      // floor & cap
      if (estimatedBfp < 1) estimatedBfp = 1;
      if (estimatedBfp > 60) estimatedBfp = 60;

      setState(() {
        _bodyFatController.text = estimatedBfp.toStringAsFixed(1);
        _useBfpEstimator = false;
        _calculateFfmi(); // optionally update FFMI
      });

      // close any open dialog
      Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      _showErrorDialog(
        "Calculation Error: ${e is ArgumentError ? e.message : 'Invalid input for BFP calculation.'}",
      );
    }
  }

  void _showBfpEstimatorDialog() {
    // Reset previous values if needed
    _neckController.clear();
    _waistController.clear();
    _hipController.clear();

    showCupertinoModalPopup(
      context:
          context, // This is the State's context, fine for launching the popup
      builder:
          (BuildContext dialogContext) => CupertinoActionSheet(
            // <--- Use this context inside
            title: const Text("Estimate Body Fat % (US Navy Method)"),
            message: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize:
                    MainAxisSize.min, // Important for Column in ActionSheet
                children: [
                  Text(
                    "Enter measurements in CM:",
                    style: CupertinoTheme.of(dialogContext).textTheme.textStyle,
                  ),
                  const SizedBox(height: 10),
                  _buildTextField(
                    _neckController,
                    "Neck (cm)",
                    TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  _buildTextField(
                    _waistController,
                    "Waist (cm)",
                    TextInputType.number,
                  ),
                  if (_selectedGender == Gender.female) ...[
                    const SizedBox(height: 8),
                    _buildTextField(
                      _hipController,
                      "Hip (cm)",
                      TextInputType.number,
                    ),
                  ],
                  const SizedBox(height: 15),
                  CupertinoButton.filled(
                    onPressed: _calculateAndSetBfp,
                    child: const Text("Calculate & Use BFP"),
                  ),
                ],
              ),
            ),
            cancelButton: CupertinoActionSheetAction(
              child: const Text('Cancel'),
              onPressed: () {
                // Use the dialogContext to pop this specific route
                Navigator.pop(dialogContext);
              },
            ),
          ),
    );
  }

  void _calculateFfmi() {
    final weightKg = _getWeightInKg();
    final heightM = _getHeightInM();
    final bodyFatPercentage = double.tryParse(_bodyFatController.text) ?? -1.0;
    _ffmiGoal = double.tryParse(
      _ffmiGoalController.text,
    ); // Update goal on calc

    if (weightKg <= 0 ||
        heightM <= 0 ||
        bodyFatPercentage < 0 ||
        bodyFatPercentage >= 100) {
      _showErrorDialog(
        "Please enter valid weight, height, and body fat percentage (0-99).",
      );
      setState(() {
        _ffmiResult = null;
        _adjustedFfmiResult = null;
        _lbmResult = null;
        _interpretation = null;
      });
      return;
    }

    // LBM = Weight * (1 - (BFP / 100))
    final lbm = weightKg * (1 - (bodyFatPercentage / 100));

    // FFMI = LBM[kg] / (Height[m]^2)
    final ffmi = lbm / (heightM * heightM);

    // Adjusted FFMI = FFMI + 6.1 * (1.8 - Height[m]) --- common adjustment
    final adjustedFfmi = ffmi + (6.1 * (1.8 - heightM));

    setState(() {
      _lbmResult = lbm;
      _ffmiResult = ffmi;
      _adjustedFfmiResult = adjustedFfmi;
      _interpretation = FfmiRanges.getInterpretation(ffmi, _selectedGender);
    });
    _saveUserData();
  }

  void _showErrorDialog(String message) {
    showCupertinoDialog(
      context: context,
      builder:
          (context) => CupertinoAlertDialog(
            title: const Text('Invalid Input'),
            content: Text(message),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    _heightCmController.dispose();
    _heightFtController.dispose();
    _heightInController.dispose();
    _bodyFatController.dispose();
    _ffmiGoalController.dispose();
    _neckController.dispose();
    _waistController.dispose();
    _hipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('FFMI Calculator'),
      ),
      child: SafeArea(
        child: ListView(
          // Use ListView to prevent overflow on smaller screens
          padding: const EdgeInsets.all(16.0),
          children: [
            // --- Gender Selection ---
            _buildSectionTitle("Gender"),
            CupertinoSegmentedControl<Gender>(
              children: const {
                Gender.male: Padding(
                  padding: EdgeInsets.all(8),
                  child: Text("Male"),
                ),
                Gender.female: Padding(
                  padding: EdgeInsets.all(8),
                  child: Text("Female"),
                ),
              },
              onValueChanged: (Gender value) {
                setState(() {
                  _selectedGender = value;
                  // Recalculate if results exist, as interpretation changes
                  if (_ffmiResult != null) _calculateFfmi();
                });
              },
              groupValue: _selectedGender,
            ),
            const SizedBox(height: 16),

            // --- Weight Input ---
            _buildSectionTitle("Weight"),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    _weightController,
                    "Weight",
                    TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 10),
                CupertinoSegmentedControl<WeightUnit>(
                  children: const {
                    WeightUnit.kg: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text("kg"),
                    ),
                    WeightUnit.lbs: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text("lbs"),
                    ),
                  },
                  groupValue: _selectedWeightUnit,
                  onValueChanged: (value) {
                    setState(() => _selectedWeightUnit = value);
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // --- Height Input ---
            _buildSectionTitle("Height"),
            CupertinoSegmentedControl<HeightUnit>(
              children: const {
                HeightUnit.cm: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text("cm"),
                ),
                HeightUnit.ftIn: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text("ft, in"),
                ),
              },
              groupValue: _selectedHeightUnit,
              onValueChanged: (value) {
                setState(() => _selectedHeightUnit = value);
                // Clear other unit fields when switching
                if (value == HeightUnit.cm) {
                  _heightFtController.clear();
                  _heightInController.clear();
                } else {
                  _heightCmController.clear();
                }
              },
            ),
            const SizedBox(height: 5),
            if (_selectedHeightUnit == HeightUnit.cm)
              _buildTextField(
                _heightCmController,
                "Height (cm)",
                TextInputType.numberWithOptions(decimal: true),
              ),
            if (_selectedHeightUnit == HeightUnit.ftIn)
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      _heightFtController,
                      "Feet",
                      TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      _heightInController,
                      "Inches",
                      TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 16),

            // --- Body Fat Input ---
            _buildSectionTitle("Body Fat Percentage (%)"),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    _bodyFatController,
                    "Body Fat %",
                    TextInputType.numberWithOptions(decimal: true),
                    enabled: !_useBfpEstimator, // Disable if using estimator
                  ),
                ),
                const SizedBox(width: 10),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    _useBfpEstimator ? "Enter Manually" : "Estimate BFP",
                  ),
                  onPressed: () {
                    // If user wants to estimate, show dialog.
                    // If estimation was active and they click again, let them enter manually.
                    if (!_useBfpEstimator) {
                      _showBfpEstimatorDialog();
                      // // Optionally clear the manual field when opening estimator
                      // _bodyFatController.clear();
                      // setState(() {
                      //   _useBfpEstimator = true; // Set flag visually (optional)
                      // });
                    } else {
                      setState(() {
                        _useBfpEstimator = false; // Allow manual input again
                      });
                    }
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),

            // --- Calculate Button ---
            CupertinoButton.filled(
              onPressed: _calculateFfmi,
              child: const Text('Calculate FFMI'),
            ),
            const SizedBox(height: 24),

            // --- Results Section ---
            if (_ffmiResult != null) ...[
              _buildSectionTitle("Results"),
              _buildResultRow(
                "Lean Body Mass (LBM):",
                "${_lbmResult?.toStringAsFixed(1)} kg",
              ),
              _buildResultRow("FFMI:", _ffmiResult!.toStringAsFixed(1)),
              _buildResultRow(
                "Adjusted FFMI:",
                _adjustedFfmiResult!.toStringAsFixed(1),
              ),
              _buildResultRow(
                "Interpretation:",
                _interpretation ?? "N/A",
                isInterpretation: true,
              ),
              const SizedBox(height: 20),

              // --- FFMI Ranges Progress Bars ---
              _buildSectionTitle("FFMI Ranges (${_selectedGender.name})"),
              _buildFfmiRangeBars(_ffmiResult!, _selectedGender),

              const SizedBox(height: 20),

              // --- Goal Section ---
              _buildSectionTitle("FFMI Goal"),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      _ffmiGoalController,
                      "Enter FFMI Goal",
                      TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  // Optionally add a button to 'Set Goal' if needed separate from calc
                ],
              ),
              const SizedBox(height: 10),
              if (_ffmiGoal != null && _ffmiGoal! > 0)
                _buildGoalProgress(_ffmiResult!, _ffmiGoal!),
            ], // End of results section
          ],
        ),
      ),
    );
  }

  // --- Widget Builder Helpers ---

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 5.0),
      child: Text(
        title,
        style: CupertinoTheme.of(
          context,
        ).textTheme.navTitleTextStyle.copyWith(fontSize: 18),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String placeholder,
    TextInputType keyboardType, {
    bool enabled = true,
  }) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      keyboardType: keyboardType,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color:
            enabled
                ? CupertinoColors.systemBackground
                : CupertinoColors.systemGrey5,
        border: Border.all(color: CupertinoColors.systemGrey4),
        borderRadius: BorderRadius.circular(8.0),
      ),
      readOnly: !enabled,
      style: TextStyle(
        color: enabled ? CupertinoColors.label : CupertinoColors.secondaryLabel,
      ),
    );
  }

  Widget _buildResultRow(
    String label,
    String value, {
    bool isInterpretation = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: CupertinoTheme.of(context).textTheme.textStyle),
          Text(
            value,
            style:
                isInterpretation
                    ? CupertinoTheme.of(
                      context,
                    ).textTheme.textStyle.copyWith(fontWeight: FontWeight.bold)
                    : CupertinoTheme.of(context).textTheme.textStyle,
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }

  Widget _buildFfmiRangeBars(double currentFfmi, Gender gender) {
    final rangeLabels = FfmiRanges.labels[gender]!;
    final thresholds = FfmiRanges.thresholds[gender]!;
    final currentRangeIndex = FfmiRanges.getRangeIndex(currentFfmi, gender);

    // Define a max value for scaling the bars reasonably (e.g., 30 for men, 25 for women)
    final double maxFfmiForBar = gender == Gender.male ? 30.0 : 25.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(rangeLabels.length, (index) {
        final label = FfmiRanges.ranges[gender]!.keys.elementAt(index);
        final rangeText = rangeLabels[index];
        final lowerBound = thresholds[index];
        final upperBound =
            (index < thresholds.length - 1)
                ? thresholds[index + 1]
                : maxFfmiForBar; // Use max for last bar

        // Calculate progress within this specific range segment IF current FFMI falls here
        double progressInRange = 0;
        if (currentRangeIndex == index && upperBound > lowerBound) {
          progressInRange =
              (currentFfmi - lowerBound) / (upperBound - lowerBound);
          progressInRange = progressInRange.clamp(
            0.0,
            1.0,
          ); // Ensure it's between 0 and 1
        } else if (currentRangeIndex > index) {
          progressInRange = 1.0; // Fully filled if FFMI is beyond this range
        }

        bool isCurrentRange = index == currentRangeIndex;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: CupertinoTheme.of(
                      context,
                    ).textTheme.textStyle.copyWith(
                      fontWeight:
                          isCurrentRange ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  Text(
                    rangeText,
                    style: CupertinoTheme.of(
                      context,
                    ).textTheme.textStyle.copyWith(
                      color: CupertinoColors.secondaryLabel,
                      fontWeight:
                          isCurrentRange ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                // Using Material's for simplicity
                value: progressInRange,
                backgroundColor: CupertinoColors.systemGrey5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isCurrentRange
                      ? CupertinoColors.systemGreen
                      : CupertinoColors
                          .systemGrey, // Highlight current range bar
                ),
                minHeight: 8, // Make bars thicker
              ),
              if (isCurrentRange)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    "Current: ${currentFfmi.toStringAsFixed(1)}",
                    style: CupertinoTheme.of(
                      context,
                    ).textTheme.tabLabelTextStyle.copyWith(
                      color: CupertinoColors.systemGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildGoalProgress(double currentFfmi, double goalFfmi) {
    if (goalFfmi <= 0) {
      return const SizedBox.shrink(); // Don't show if goal is invalid
    }

    final double progress = (currentFfmi / goalFfmi).clamp(
      0.0,
      1.0,
    ); // Cap at 100%

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Progress to Goal (${goalFfmi.toStringAsFixed(1)}):",
              style: CupertinoTheme.of(context).textTheme.textStyle,
            ),
            Text("${(progress * 100).toStringAsFixed(0)}%"),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: CupertinoColors.systemGrey5,
          valueColor: const AlwaysStoppedAnimation<Color>(
            CupertinoColors.systemBlue,
          ),
          minHeight: 10,
        ),
      ],
    );
  }
}
