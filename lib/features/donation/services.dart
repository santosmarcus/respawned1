import 'models.dart';

class DonationService {
  final List<Organization> _mockOrganizations = <Organization>[
    Organization(
      id: '1',
      name: 'Org 1',
      location: 'Place, Region',
      website: 'https://one.org/',
      isFavorite: true,
    ),
    Organization(
      id: '2',
      name: 'Org 2',
      location: 'Place, Region',
      website: 'https://two.com/',
      isFavorite: false,
      hasSpotify: false,
    ),
    Organization(
      id: '3',
      name: 'Org 3',
      location: 'Place, Region',
      website: 'https://three.ph/',
      isFavorite: false,
      hasFacebook: false,
      hasInstagram: false,
      hasSpotify: false,
    ),
    Organization(
      id: '4',
      name: 'Org 4',
      location: 'Place, Region',
      website: 'https://four.org/',
      isFavorite: true,
      hasEmail: false,
    ),
    Organization(
      id: '5',
      name: 'Org 5',
      location: 'Place, Region',
      website: 'https://five.net/',
      isFavorite: false,
      hasFacebook: false,
    ),
  ];

  final List<Fundraiser> _mockFundraisers = <Fundraiser>[
    Fundraiser(
      id: '1',
      name: 'Campaign 1',
      description: 'Description 1',
      targetAmount: 5000.0,
      currentAmount: 2000.0,
      isFavorite: true,
      daysLeft: 10,
    ),
    Fundraiser(
      id: '2',
      name: 'Campaign 2',
      description: 'Description 2',
      targetAmount: 10000.0,
      currentAmount: 2000.0,
      isFavorite: false,
      daysLeft: 30,
    ),
    Fundraiser(
      id: '3',
      name: 'Campaign 3',
      description: 'Description 3',
      targetAmount: 2500.0,
      currentAmount: 2500.0,
      isFavorite: true,
      daysLeft: 5,
    ),
    Fundraiser(
      id: '4',
      name: 'Campaign 4',
      description: 'Description 4',
      targetAmount: 1500.0,
      currentAmount: 0.0,
      isFavorite: false,
      daysLeft: 7,
    ),
  ];

  Future<List<Organization>> fetchOrganizations() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return _mockOrganizations;
  }

  Future<List<Fundraiser>> fetchFundraisers() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return _mockFundraisers;
  }
}
