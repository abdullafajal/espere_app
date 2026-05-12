/// API service — handles all HTTP requests to Django backend.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../models/user.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import '../models/dashboard.dart';

/// Result wrapper for API calls
class ApiResult<T> {
  final T? data;
  final String? error;
  final Map<String, dynamic>? errors;

  ApiResult({this.data, this.error, this.errors});

  bool get isSuccess => error == null && errors == null;
}

class ApiService {
  /// ─── HTTP Helpers ──────────────────────────────────────────────────────

  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final token = await AuthService.getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  static Future<String> _url(String path) async {
    final base = await AuthService.getBaseUrl();
    return '$base$path';
  }

  /// ─── Auth ──────────────────────────────────────────────────────────────

  /// Login — returns token and user data
  static Future<ApiResult<Map<String, dynamic>>> login(
      String username, String password) async {
    try {
      final url = await _url('/api/auth/login/');
      final response = await http.post(
        Uri.parse(url),
        headers: await _headers(auth: false),
        body: jsonEncode({'username': username, 'password': password}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        await AuthService.setToken(data['token']);
        return ApiResult(data: data);
      }
      return ApiResult(error: data['error'] ?? 'Login failed.');
    } catch (e) {
      return ApiResult(error: 'Connection error. Please check your server.');
    }
  }

  /// Register — creates user and returns token
  static Future<ApiResult<Map<String, dynamic>>> register(
      String username, String email, String password, String password2) async {
    try {
      final url = await _url('/api/auth/register/');
      final response = await http.post(
        Uri.parse(url),
        headers: await _headers(auth: false),
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
          'password2': password2,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        await AuthService.setToken(data['token']);
        return ApiResult(data: data);
      }
      if (data.containsKey('errors')) {
        return ApiResult(errors: data['errors']);
      }
      return ApiResult(error: data['error'] ?? 'Registration failed.');
    } catch (e) {
      return ApiResult(error: 'Connection error. Please check your server.');
    }
  }

  /// Get user profile
  static Future<ApiResult<UserModel>> getProfile() async {
    try {
      final url = await _url('/api/auth/profile/');
      final response = await http.get(
        Uri.parse(url),
        headers: await _headers(),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return ApiResult(data: UserModel.fromJson(data['user']));
      }
      return ApiResult(error: data['error'] ?? 'Failed to load profile.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Update user profile
  static Future<ApiResult<UserModel>> updateProfile(
      Map<String, dynamic> updates) async {
    try {
      final url = await _url('/api/auth/profile/');
      final response = await http.put(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode(updates),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return ApiResult(data: UserModel.fromJson(data['user']));
      }
      return ApiResult(error: data['error'] ?? 'Failed to update profile.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// ─── Dashboard ─────────────────────────────────────────────────────────

  static Future<ApiResult<DashboardData>> getDashboard() async {
    try {
      final url = await _url('/api/dashboard/');
      final response = await http.get(
        Uri.parse(url),
        headers: await _headers(),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return ApiResult(data: DashboardData.fromJson(data));
      }
      return ApiResult(error: data['error'] ?? 'Failed to load dashboard.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// ─── Transactions ──────────────────────────────────────────────────────

  /// Get transactions with optional filters
  static Future<ApiResult<Map<String, dynamic>>> getTransactions({
    String? query,
    String? type,
    int? categoryId,
    String? month,
    bool showAll = false,
    int page = 1,
  }) async {
    try {
      final params = <String, String>{};
      if (query != null && query.isNotEmpty) params['q'] = query;
      if (type != null && type.isNotEmpty) params['type'] = type;
      if (categoryId != null) params['category'] = categoryId.toString();
      if (showAll) {
        params['all'] = '1';
      } else if (month != null) {
        params['month'] = month;
      }
      params['page'] = page.toString();

      final baseUrl = await _url('/api/transactions/');
      final uri = Uri.parse(baseUrl).replace(queryParameters: params);
      final response = await http.get(uri, headers: await _headers());

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final transactions = (data['transactions'] as List)
            .map((t) => TransactionModel.fromJson(t))
            .toList();
        return ApiResult(data: {
          'transactions': transactions,
          'currency_symbol': data['currency_symbol'] ?? '₹',
          'total': data['total'],
          'has_next': data['has_next'],
        });
      }
      return ApiResult(error: data['error'] ?? 'Failed to load transactions.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Create a transaction
  static Future<ApiResult<TransactionModel>> createTransaction(
      Map<String, dynamic> txnData) async {
    try {
      final url = await _url('/api/transactions/');
      final response = await http.post(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode(txnData),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return ApiResult(
            data: TransactionModel.fromJson(data['transaction']));
      }
      if (data.containsKey('errors')) {
        return ApiResult(errors: data['errors']);
      }
      return ApiResult(error: 'Failed to create transaction.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Update a transaction
  static Future<ApiResult<TransactionModel>> updateTransaction(
      int id, Map<String, dynamic> txnData) async {
    try {
      final url = await _url('/api/transactions/$id/');
      final response = await http.put(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode(txnData),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return ApiResult(
            data: TransactionModel.fromJson(data['transaction']));
      }
      return ApiResult(error: 'Failed to update transaction.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Delete a transaction
  static Future<ApiResult<bool>> deleteTransaction(int id) async {
    try {
      final url = await _url('/api/transactions/$id/');
      final response = await http.delete(
        Uri.parse(url),
        headers: await _headers(),
      );

      if (response.statusCode == 200) {
        return ApiResult(data: true);
      }
      return ApiResult(error: 'Failed to delete transaction.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// ─── Categories ────────────────────────────────────────────────────────

  static Future<ApiResult<Map<String, dynamic>>> getCategories() async {
    try {
      final url = await _url('/api/categories/');
      final response = await http.get(
        Uri.parse(url),
        headers: await _headers(),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final categories = (data['categories'] as List)
            .map((c) => CategoryModel.fromJson(c))
            .toList();
        return ApiResult(data: {
          'categories': categories,
          'currency_symbol': data['currency_symbol'] ?? '₹',
        });
      }
      return ApiResult(error: 'Failed to load categories.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Create a new user category
  static Future<ApiResult<CategoryModel>> createCategory(
      Map<String, dynamic> catData) async {
    try {
      final url = await _url('/api/categories/');
      final response = await http.post(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode(catData),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return ApiResult(data: CategoryModel.fromJson(data['category']));
      }
      return ApiResult(error: data['error'] ?? 'Failed to create category.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Update an existing user category
  static Future<ApiResult<CategoryModel>> updateCategory(
      int id, Map<String, dynamic> catData) async {
    try {
      final url = await _url('/api/categories/$id/');
      final response = await http.put(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode(catData),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return ApiResult(data: CategoryModel.fromJson(data['category']));
      }
      return ApiResult(error: data['error'] ?? 'Failed to update category.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Delete a user category
  static Future<ApiResult<bool>> deleteCategory(int id) async {
    try {
      final url = await _url('/api/categories/$id/');
      final response = await http.delete(
        Uri.parse(url),
        headers: await _headers(),
      );

      if (response.statusCode == 200) {
        return ApiResult(data: true);
      }
      final data = jsonDecode(response.body);
      return ApiResult(error: data['error'] ?? 'Failed to delete category.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// ─── Budgets ─────────────────────────────────────────────────────────

  static Future<ApiResult<Map<String, dynamic>>> getBudgets() async {
    try {
      final url = await _url('/api/budgets/');
      final response = await http.get(
        Uri.parse(url),
        headers: await _headers(),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return ApiResult(data: data);
      }
      return ApiResult(error: data['error'] ?? 'Failed to load budgets.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  static Future<ApiResult<Map<String, dynamic>>> createBudget(Map<String, dynamic> body) async {
    try {
      final url = await _url('/api/budgets/');
      final response = await http.post(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode(body),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return ApiResult(data: data['budget']);
      }
      return ApiResult(error: data['error'] ?? 'Failed to save budget.', errors: data['errors']);
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  static Future<ApiResult<void>> deleteBudget(int id) async {
    try {
      final url = await _url('/api/budgets/$id/');
      final response = await http.delete(Uri.parse(url), headers: await _headers());
      if (response.statusCode == 200) {
        return ApiResult(data: null);
      }
      final data = jsonDecode(response.body);
      return ApiResult(error: data['error'] ?? 'Failed to delete budget.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// ─── Reports ─────────────────────────────────────────────────────────

  /// Get report data
  static Future<ApiResult<Map<String, dynamic>>> getReports({int? year}) async {
    try {
      final y = year ?? DateTime.now().year;
      final url = await _url('/api/reports/?year=$y');
      final response = await http.get(Uri.parse(url), headers: await _headers());

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return ApiResult(data: data);
      }
      return ApiResult(error: data['error'] ?? 'Failed to load reports.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// ─── Savings ─────────────────────────────────────────────────────────
  /// Get savings goals
  static Future<ApiResult<Map<String, dynamic>>> getSavings() async {
    try {
      final url = await _url('/api/savings/');
      final response = await http.get(
        Uri.parse(url),
        headers: await _headers(),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return ApiResult(data: data);
      }
      return ApiResult(error: 'Failed to load savings.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Create a new savings goal
  static Future<ApiResult<Map<String, dynamic>>> createSavingGoal(
      Map<String, dynamic> goalData) async {
    try {
      final url = await _url('/api/savings/');
      final response = await http.post(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode(goalData),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return ApiResult(data: data['goal']);
      }
      return ApiResult(error: data['error'] ?? 'Failed to create goal.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Update a savings goal
  static Future<ApiResult<Map<String, dynamic>>> updateSavingGoal(
      int id, Map<String, dynamic> goalData) async {
    try {
      final url = await _url('/api/savings/$id/');
      final response = await http.put(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode(goalData),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return ApiResult(data: data['goal']);
      }
      return ApiResult(error: data['error'] ?? 'Failed to update goal.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Delete a savings goal
  static Future<ApiResult<bool>> deleteSavingGoal(int id) async {
    try {
      final url = await _url('/api/savings/$id/');
      final response =
          await http.delete(Uri.parse(url), headers: await _headers());

      if (response.statusCode == 200) {
        return ApiResult(data: true);
      }
      return ApiResult(error: 'Failed to delete goal.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Add money to a savings goal
  static Future<ApiResult<Map<String, dynamic>>> addMoneyToSavingGoal(
      int id, double amount, {String? notes}) async {
    try {
      final url = await _url('/api/savings/$id/add-money/');
      final response = await http.post(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode({
          'amount': amount,
          'notes': notes ?? '',
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return ApiResult(data: data['goal']);
      }
      return ApiResult(error: data['error'] ?? 'Failed to add money.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// ─── Split Expense ───────────────────────────────────────────────────

  static Future<ApiResult<List<Map<String, dynamic>>>> getSplitGroups() async {
    try {
      final url = await _url('/api/split/groups/');
      final response = await http.get(
        Uri.parse(url),
        headers: await _headers(),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final groups = List<Map<String, dynamic>>.from(data['groups']);
        return ApiResult(data: groups);
      }
      return ApiResult(error: 'Failed to load groups.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Create a new split group
  static Future<ApiResult<Map<String, dynamic>>> createSplitGroup(
      Map<String, dynamic> groupData) async {
    try {
      final url = await _url('/api/split/groups/');
      final response = await http.post(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode(groupData),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return ApiResult(data: Map<String, dynamic>.from(data['group']));
      }
      return ApiResult(error: data['error'] ?? 'Failed to create group.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Get group detail (members, expenses, debts, settlements)
  static Future<ApiResult<Map<String, dynamic>>> getSplitGroupDetail(int id) async {
    try {
      final url = await _url('/api/split/groups/$id/');
      final response = await http.get(
        Uri.parse(url),
        headers: await _headers(),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return ApiResult(data: Map<String, dynamic>.from(data['group']));
      }
      return ApiResult(error: 'Failed to load group.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Add an expense to a group
  static Future<ApiResult<Map<String, dynamic>>> addSplitExpense(
      int groupId, Map<String, dynamic> expenseData) async {
    try {
      final url = await _url('/api/split/groups/$groupId/expenses/');
      final response = await http.post(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode(expenseData),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return ApiResult(data: Map<String, dynamic>.from(data['expense']));
      }
      return ApiResult(error: data['error'] ?? 'Failed to add expense.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Settle a debt in a group
  static Future<ApiResult<Map<String, dynamic>>> settleDebt(
      int groupId, Map<String, dynamic> settleData) async {
    try {
      final url = await _url('/api/split/groups/$groupId/settle/');
      final response = await http.post(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode(settleData),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return ApiResult(data: Map<String, dynamic>.from(data['settlement']));
      }
      return ApiResult(error: data['error'] ?? 'Failed to settle.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }
  /// Add a member to a group by username/email
  static Future<ApiResult<Map<String, dynamic>>> addSplitMember(
      int groupId, String identifier) async {
    try {
      final url = await _url('/api/split/groups/$groupId/members/');
      final response = await http.post(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode({'identifier': identifier}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return ApiResult(data: Map<String, dynamic>.from(data['member']));
      }
      return ApiResult(error: data['error'] ?? 'Failed to add member.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Register FCM device token
  static Future<ApiResult<void>> registerDeviceToken(String token) async {
    try {
      final url = await _url('/api/devices/register/');
      final response = await http.post(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode({'token': token}),
      );
      if (response.statusCode == 200) {
        return ApiResult(data: null);
      }
      return ApiResult(error: 'Failed to register token.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Search users by username/email
  static Future<ApiResult<List<Map<String, dynamic>>>> searchUsers(String query) async {
    try {
      final url = await _url('/api/split/users/search/?q=$query');
      final response = await http.get(Uri.parse(url), headers: await _headers());
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return ApiResult(data: List<Map<String, dynamic>>.from(data['users']));
      }
      return ApiResult(error: 'Search failed.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Send email reminder to a user
  static Future<ApiResult<void>> sendSplitReminder(int groupId, Map<String, dynamic> body) async {
    try {
      final url = await _url('/api/split/groups/$groupId/remind/');
      final response = await http.post(
        Uri.parse(url),
        headers: await _headers(),
        body: jsonEncode(body),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return ApiResult(data: null);
      }
      return ApiResult(error: data['error'] ?? 'Failed to send reminder.');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }

  /// Logout — notify backend and clear local token
  static Future<void> logout() async {
    try {
      final url = await _url('/api/auth/logout/');
      await http.post(
        Uri.parse(url),
        headers: await _headers(),
      );
    } catch (_) {
      // Ignore errors on logout
    }
    await AuthService.clearToken();
  }

  /// Get the full URL for CSV export
  static Future<String> getExportUrl(String period,
      {String? startDate, String? endDate}) async {
    final base = await AuthService.getBaseUrl();
    var url = '$base/reports/export/csv/?period=$period';
    if (startDate != null) url += '&start_date=$startDate';
    if (endDate != null) url += '&end_date=$endDate';
    return url;
  }

  /// Download CSV data
  static Future<ApiResult<String>> downloadCSV(String period,
      {String? startDate, String? endDate}) async {
    try {
      final url = await getExportUrl(period,
          startDate: startDate, endDate: endDate);
      final response = await http.get(
        Uri.parse(url),
        headers: await _headers(),
      );
      if (response.statusCode == 200) {
        return ApiResult(data: response.body);
      }
      return ApiResult(error: 'Failed to download CSV: ${response.statusCode}');
    } catch (e) {
      return ApiResult(error: 'Connection error.');
    }
  }
}
