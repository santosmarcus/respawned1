import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'donation_admin_models.dart';

class DonationAdminProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // State Fields - Campaigns
  String _searchQuery = "";
  int _selectedTabIndex = 0;

  // State Fields - Donations Search
  String _donationSearchQuery = "";
  String _donationCampaignQuery = "";
  String _statusFilter = "All"; // "All", "In-Progress", "Complete"
  DateTime? _startDate;
  DateTime? _endDate;
  int _donationTabIndex = 0;

  List<DonationCampaign> _campaigns = [];
  List<DonationHistoryRecord> _recentDonations = [];
  List<DonationHistoryRecord> _allDonations = [];
  List<FundAllocation> _fundAllocations = [];

  StreamSubscription? _campaignsSub;
  StreamSubscription? _donationsSub;
  StreamSubscription? _allDonationsSub;
  StreamSubscription? _fundsSub;

  DonationAdminProvider() {
    _initCampaignsListener();
    _initDonationsListener();
    _initAllDonationsListener();
  }

  void _initCampaignsListener() {
    _campaignsSub = _firestore
        .collection('campaigns')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      _campaigns = snapshot.docs
          .map((doc) => DonationCampaign.fromFirestore(doc))
          .toList();
      notifyListeners();
    });
  }

  void _initDonationsListener() {
    _donationsSub = _firestore
        .collection('donations')
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .listen((snapshot) {
      _recentDonations = snapshot.docs
          .map((doc) => DonationHistoryRecord.fromFirestore(doc))
          .toList();
      notifyListeners();
    });
  }

  void _initAllDonationsListener() {
    _allDonationsSub = _firestore
        .collection('donations')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      _allDonations = snapshot.docs
          .map((doc) => DonationHistoryRecord.fromFirestore(doc))
          .toList();
      notifyListeners();
    });
  }

  void fetchFundAllocations(String campaignId) {
    _fundsSub?.cancel();
    _fundsSub = _firestore
        .collection('funds')
        .where('campaignId', isEqualTo: campaignId)
        .snapshots()
        .listen((snapshot) {
      _fundAllocations = snapshot.docs
          .map((doc) => FundAllocation.fromFirestore(doc))
          .toList();
      
      // Client-side sorting
      _fundAllocations.sort((a, b) {
        if (a.createdAt == null) return 1;
        if (b.createdAt == null) return -1;
        return b.createdAt!.compareTo(a.createdAt!);
      });

      notifyListeners();
    });
  }

  @override
  void dispose() {
    _campaignsSub?.cancel();
    _donationsSub?.cancel();
    _allDonationsSub?.cancel();
    _fundsSub?.cancel();
    super.dispose();
  }

  // Helper to get campaign title from ID
  String getCampaignTitle(String campaignId) {
    if (campaignId.isEmpty) return "General Donation";
    final campaign = _campaigns.cast<DonationCampaign?>().firstWhere(
      (c) => c?.id == campaignId,
      orElse: () => null,
    );
    return campaign?.title ?? campaignId;
  }

  // Helper to get animal name from campaign ID
  String getAnimalName(String campaignId) {
    if (campaignId.isEmpty) return "N/A";
    final campaign = _campaigns.cast<DonationCampaign?>().firstWhere(
      (c) => c?.id == campaignId,
      orElse: () => null,
    );
    return campaign?.animalName ?? "N/A";
  }

  // Getters - Campaigns
  String get searchQuery => _searchQuery;
  int get selectedTabIndex => _selectedTabIndex;
  List<DonationCampaign> get campaigns => _campaigns;
  List<DonationHistoryRecord> get recentDonations => _recentDonations;
  List<FundAllocation> get fundAllocations => List.unmodifiable(_fundAllocations);

  // Getters - Donations Search
  String get donationSearchQuery => _donationSearchQuery;
  String get donationCampaignQuery => _donationCampaignQuery;
  String get statusFilter => _statusFilter;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;
  int get donationTabIndex => _donationTabIndex;

  List<DonationCampaign> get filteredCampaigns {
    const categories = ["all", "donation", "sponsorship"];
    String currentCategory = categories[_selectedTabIndex];

    return _campaigns.where((item) {
      final matchesSearch = item.title.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesTab = currentCategory == "all" || item.type == currentCategory;
      return matchesSearch && matchesTab;
    }).toList();
  }

  List<DonationHistoryRecord> get filteredDonations {
    return _allDonations.where((item) {
      // Exclude cancelled in-kind donations
      if (item.type == 'inkind' && item.status == 'cancelled') return false;

      // Tab Filter: 0-All, 1-Monetary, 2-Sponsorship, 3-In-Kind
      bool matchesTab = _donationTabIndex == 0 ||
          (_donationTabIndex == 1 && item.type == 'donation') ||
          (_donationTabIndex == 2 && item.type == 'sponsorship') ||
          (_donationTabIndex == 3 && item.type == 'inkind');

      if (!matchesTab) return false;

      bool matchesSearch = item.donorName.toLowerCase().contains(_donationSearchQuery.toLowerCase());
      
      final campaignTitle = getCampaignTitle(item.campaignId);
      bool matchesCampaign = campaignTitle.toLowerCase().contains(_donationCampaignQuery.toLowerCase());
      
      final date = item.timestamp?.toDate();
      bool matchesDate = date == null || ((_startDate == null || date.isAfter(_startDate!.subtract(const Duration(days: 1)))) &&
          (_endDate == null || date.isBefore(_endDate!.add(const Duration(days: 1)))));
      
      if (!matchesSearch || !matchesCampaign || !matchesDate) return false;

      // Status Filter
      if (_statusFilter == "All") return true;

      if (item.type == 'inkind') {
        final s = item.status.toLowerCase();
        // Database uses 'inprogress' (lowercase, no hyphen)
        final isInProgress = s == 'inprogress' || s == 'pending' || s == '';
        final isComplete = s == 'complete' || s == 'completed';
        
        if (_statusFilter == "In-Progress") return isInProgress;
        if (_statusFilter == "Complete") return isComplete;
      } else if (item.type == 'sponsorship') {
        final s = item.status.toLowerCase();
        final now = DateTime.now();
        final nextCharge = item.nextChargeDate?.toDate();
        
        bool isActive = false;
        if (s == 'active') {
          // Grace period: Active until nextChargeDate + 7 days
          if (nextCharge == null) {
            isActive = true;
          } else {
            isActive = now.isBefore(nextCharge.add(const Duration(days: 7)));
          }
        } else if (s == 'cancelled') {
          // Intentional cancellation: Active only until nextChargeDate (no grace)
          if (nextCharge == null) {
            isActive = false; 
          } else {
            isActive = now.isBefore(nextCharge);
          }
        }
        
        if (_statusFilter == "Active") return isActive;
        if (_statusFilter == "Inactive") return !isActive;
      }

      return true;
    }).toList();
  }

  // Setters / Actions - Campaigns
  void updateSearch(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void updateTab(int index) {
    _selectedTabIndex = index;
    notifyListeners();
  }

  // Setters / Actions - Donations Search
  void updateDonationSearch(String query) {
    _donationSearchQuery = query;
    notifyListeners();
  }

  void updateDonationCampaignSearch(String query) {
    _donationCampaignQuery = query;
    notifyListeners();
  }

  void updateDonationDates(DateTime? start, DateTime? end) {
    _startDate = start;
    _endDate = end;
    notifyListeners();
  }

  void updateDonationTab(int index) {
    _donationTabIndex = index;
    _statusFilter = "All"; // Reset filter when switching tabs
    notifyListeners();
  }

  void updateStatusFilter(String status) {
    _statusFilter = status;
    notifyListeners();
  }

  Future<void> addCampaign(DonationCampaign campaign) async {
    await _firestore.collection('campaigns').add(campaign.toMap());
  }

  Future<void> addFundAllocation(FundAllocation allocation) async {
    await _firestore.collection('funds').add(allocation.toMap());
  }

  Future<void> updateCampaign(String id, Map<String, dynamic> data) async {
    await _firestore.collection('campaigns').doc(id).update(data);
  }

  Future<void> markDonationAsComplete(String donationId, String userId, String organizerName) async {
    final batch = _firestore.batch();
    
    final donationRef = _firestore.collection('donations').doc(donationId);
    batch.update(donationRef, {'status': 'complete'});
    
    final userHistoryRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('history')
        .doc(donationId);
    
    // Check if the document exists in user history before updating
    final userHistoryDoc = await userHistoryRef.get();
    if (userHistoryDoc.exists) {
      batch.update(userHistoryRef, {'status': 'complete'});
    }

    await batch.commit();
  }

  Future<void> sendInKindFollowUpNotification(String donationId, String userId, String campaignTitle) async {
    final notifRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc();
    
    await notifRef.set({
      'title': 'In-Kind Donation Follow-up',
      'message': 'We are following up on your in-kind donation for $campaignTitle. Please let us know if you have any updates!',
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      'type': 'inkind_followup',
      'donationId': donationId,
    });
  }

  Future<void> endCampaign(String campaignId, String type, String campaignTitle, String animalName) async {
    final batch = _firestore.batch();
    
    // 1. Update campaign status
    final campaignRef = _firestore.collection('campaigns').doc(campaignId);
    final Map<String, dynamic> updateData = {'isActive': false};
    if (type == 'donation') {
      updateData['date'] = Timestamp.now();
    }
    batch.update(campaignRef, updateData);
    
    if (type == 'sponsorship') {
      // 2. Find and update all active sponsorships
      final activeSponsorships = await _firestore
          .collection('donations')
          .where('campaignId', isEqualTo: campaignId)
          .where('status', isEqualTo: 'active')
          .get();
          
      final Set<String> notifiedUserIds = {};
          
      for (final doc in activeSponsorships.docs) {
        batch.update(doc.reference, {'status': 'inactive'});
        
        final userId = doc.data()['userId'] as String?;
        if (userId != null) {
          // 3. Update user history record too
          final historyRef = _firestore
              .collection('users')
              .doc(userId)
              .collection('history')
              .doc(doc.id);
          
          final historyDoc = await historyRef.get();
          if (historyDoc.exists) {
            batch.update(historyRef, {'status': 'inactive'});
          }
        }
      }
    }
    
    await batch.commit();
  }
}
