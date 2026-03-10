import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const MyApp());
}

class Role {
  final String name;
  final String description;

  const Role({required this.name, required this.description});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Role && runtimeType == other.runtimeType && name == other.name;

  @override
  int get hashCode => name.hashCode;
}

class RoleSelectionModel extends ChangeNotifier {
  String? _selectedRoleName;
  final List<Role> _availableRoles = <Role>[
    const Role(name: 'General User', description: 'Report rescue cases, adopt animals, volunteer in events, donate or sponsor.'),
    const Role(name: 'Pet Transporter', description: 'Safe transports of rescued animals to shelters or clinics, provides progress updates, and ensures comfort during travel.'),
    const Role(name: 'Rescue Volunteer', description: 'Registered responder who can take on rescue cases when partner organizations are unavailable. Provide basic care and needs to rescue cases and ensure they are not left unattended.'),
  ];

  String? get selectedRoleName => _selectedRoleName;
  List<Role> get availableRoles => _availableRoles;

  void selectRole(String roleName) {
    if (_selectedRoleName != roleName) {
      _selectedRoleName = roleName;
      notifyListeners();
    }
  }

  void clearSelection() {
    if (_selectedRoleName != null) {
      _selectedRoleName = null;
      notifyListeners();
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ChangeNotifierProvider<RoleSelectionModel>(
        create: (BuildContext context) => RoleSelectionModel(),
        builder: (BuildContext context, Widget? child) => const Login(),
      ),
    );
  }
}

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EADC),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Fixed top text
            Padding(
              padding: const EdgeInsets.only(left: 30.0, right: 30.0, top: 30.0),
              child: Text(
                'What is your role?',
                style: GoogleFonts.tiltWarp(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 30.0),
                child: Consumer<RoleSelectionModel>(
                  builder: (BuildContext context, RoleSelectionModel model, Widget? child) {
                    return Column(
                      children: model.availableRoles.map<Widget>((Role role) {
                        final bool isSelected = model.selectedRoleName == role.name;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => model.selectRole(role.name),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 15.0),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12.0),
                                ),
                                side: BorderSide(
                                  color: isSelected ? const Color(0xFFFFD95E) : Colors.grey.shade400,
                                  width: isSelected ? 3.0 : 1.0,
                                ),
                                backgroundColor: isSelected ? const Color.fromARGB(51, 255, 217, 94) : Colors.white,
                                foregroundColor: Colors.black,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: <Widget>[
                                    Text(
                                      role.name,
                                      style: GoogleFonts.tiltWarp(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      role.description,
                                      style: GoogleFonts.zain(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 30.0, right: 30.0, bottom: 30.0),
              child: Consumer<RoleSelectionModel>(
                builder: (BuildContext context, RoleSelectionModel model, Widget? child) {
                  final bool isRoleSelected = model.selectedRoleName != null;
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isRoleSelected
                          ? () {
                              //Placeholder for redirect logic
                              debugPrint('Confirmed selected role: ${model.selectedRoleName}');
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        backgroundColor: isRoleSelected ? const Color(0xFFFFD95E) : Colors.grey.shade300,
                        foregroundColor: isRoleSelected ? Colors.black : Colors.grey.shade600,
                        textStyle: GoogleFonts.tiltWarp(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text(
                        'Continue',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}