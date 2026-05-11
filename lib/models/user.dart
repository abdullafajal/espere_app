/// User model matching Django's User + UserProfile.
class UserModel {
  final int id;
  final String username;
  final String email;
  final String firstName;
  final String lastName;
  final String avatar;
  final String currency;
  final String currencySymbol;
  final String theme;
  final bool emailReminders;

  UserModel({
    required this.id,
    required this.username,
    required this.email,
    this.firstName = '',
    this.lastName = '',
    this.avatar = '',
    this.currency = 'INR',
    this.currencySymbol = '₹',
    this.theme = 'light',
    this.emailReminders = true,
  });

  /// Full display name, falling back to username
  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isNotEmpty ? full : username;
  }

  /// First character for avatar initials
  String get initials => username.isNotEmpty ? username[0].toUpperCase() : '?';

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      avatar: json['avatar'] ?? '',
      currency: json['currency'] ?? 'INR',
      currencySymbol: json['currency_symbol'] ?? '₹',
      theme: json['theme'] ?? 'light',
      emailReminders: json['email_reminders'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'currency': currency,
        'theme': theme,
        'email_reminders': emailReminders,
      };
}
