/// The logged-in employee's basic profile, shown after a successful login.
class EmployeeProfile {
  const EmployeeProfile({
    required this.employeeId,
    required this.name,
    required this.assignedDistrict,
  });

  final String employeeId;
  final String name;
  final String? assignedDistrict;
}
