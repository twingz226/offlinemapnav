import '../data/models/favorite_place_model.dart';

class POIService {
  static final List<FavoritePlaceModel> builtinPlaces = [
    // --- Beaches & Sandbars ---
    FavoritePlaceModel(
      name: 'Rizal Boulevard Beachfront',
      latitude: 9.3088,
      longitude: 123.3106,
      description: 'Scenic waterfront promenade and beachfront named after Dr. Jose Rizal.',
    ),
    FavoritePlaceModel(
      name: 'Dauin Beach & Marine Sanctuaries',
      latitude: 9.1895,
      longitude: 123.2646,
      description: 'Beautiful sandy beach and world-renowned coral reef diving resorts.',
    ),
    FavoritePlaceModel(
      name: 'Apo Island Beach & Dive Resort',
      latitude: 9.0792,
      longitude: 123.2711,
      description: 'Famous beach resort and marine sanctuary for swimming with sea turtles.',
    ),
    FavoritePlaceModel(
      name: 'Manjuyod Sandbar Beach',
      latitude: 9.6153,
      longitude: 123.1557,
      description: 'Stunning white sandbar and cottages often called the Maldives of the Philippines.',
    ),
    FavoritePlaceModel(
      name: 'Talisay Beach Dauin',
      latitude: 9.1821,
      longitude: 123.2605,
      description: 'Quiet sandy beach with crystal clear waters in Dauin.',
    ),

    // --- Waterfalls ---
    FavoritePlaceModel(
      name: 'Casaroro Falls',
      latitude: 9.2811,
      longitude: 123.2081,
      description: 'Breathtaking single-column waterfall nestled in Valencia forest.',
    ),
    FavoritePlaceModel(
      name: 'Pulangbato Falls',
      latitude: 9.3069,
      longitude: 123.2039,
      description: 'Popular red-rock waterfall with natural swimming pools in Valencia.',
    ),
    FavoritePlaceModel(
      name: 'Niludhan Falls Bayawan',
      latitude: 9.4022,
      longitude: 122.9054,
      description: 'Stunning wide curtain waterfall in the middle of lush tropical plantations.',
    ),
    FavoritePlaceModel(
      name: 'Malabo Falls Valencia',
      latitude: 9.2890,
      longitude: 123.2201,
      description: 'Charming secondary waterfall located along the Valencia trail.',
    ),

    // --- Pools & Resorts ---
    FavoritePlaceModel(
      name: 'Tejero Highland Resort and Waterpark',
      latitude: 9.2906,
      longitude: 123.2389,
      description: 'Resort with outdoor natural spring pools and water slides.',
    ),
    FavoritePlaceModel(
      name: 'Forest Camp Riverside Resort',
      latitude: 9.2831,
      longitude: 123.2458,
      description: 'Mountain resort featuring cold spring pools, zip lines, and campsites.',
    ),
    FavoritePlaceModel(
      name: 'Tierra Alta Resort & Pool',
      latitude: 9.2974,
      longitude: 123.2566,
      description: 'Luxury hillside resort featuring a iconic lighthouse and infinity pool.',
    ),
    FavoritePlaceModel(
      name: 'Silliman University Pool',
      latitude: 9.3142,
      longitude: 123.3051,
      description: 'Olympic-size swimming pool facility at Silliman University.',
    ),

    // --- Springs ---
    FavoritePlaceModel(
      name: 'Red Rock Hot Spring',
      latitude: 9.3075,
      longitude: 123.2012,
      description: 'Relaxing natural thermal hot spring pool in Valencia.',
    ),
    FavoritePlaceModel(
      name: 'Banica Cold Spring',
      latitude: 9.2910,
      longitude: 123.2255,
      description: 'Fresh and chilly natural mountain spring water pools.',
    ),

    // --- Camps & Parks ---
    FavoritePlaceModel(
      name: 'Forest Camp Campsite',
      latitude: 9.2828,
      longitude: 123.2452,
      description: 'Eco-friendly camping and hammock ground along the river.',
    ),
    FavoritePlaceModel(
      name: 'Valencia Ridge Camping Ground',
      latitude: 9.2785,
      longitude: 123.2198,
      description: 'Scenic ridge campground offering panoramic views of Mt. Talinis.',
    ),
    FavoritePlaceModel(
      name: 'Quezon Park',
      latitude: 9.3075,
      longitude: 123.3082,
      description: 'Public park situated near the belfry and cathedral.',
    ),

    // --- Food, Cafes & Restaurants ---
    FavoritePlaceModel(
      name: 'Sans Rival Cakes and Pastries',
      latitude: 9.3078,
      longitude: 123.3102,
      description: 'Famous local bakery and cafe known for silvanas and sans rival cake.',
    ),
    FavoritePlaceModel(
      name: 'Jo\'s Chicken Inato',
      latitude: 9.3051,
      longitude: 123.3075,
      description: 'Popular restaurant serving traditional Filipino grilled chicken inato.',
    ),
    FavoritePlaceModel(
      name: 'Hayahay Treehouse Bar & Seafood',
      latitude: 9.3195,
      longitude: 123.3134,
      description: 'Relaxing seaside treehouse restaurant serving fresh seafood and pizza.',
    ),
    FavoritePlaceModel(
      name: 'Lantaw Seafood Restaurant',
      latitude: 9.3210,
      longitude: 123.3139,
      description: 'Oceanfront dining with premium Filipino and seafood dishes.',
    ),
    FavoritePlaceModel(
      name: 'Why Not Restaurant & Bar',
      latitude: 9.3082,
      longitude: 123.3108,
      description: 'Popular international pub, bakery, and Swiss restaurant on Rizal Boulevard.',
    ),
    FavoritePlaceModel(
      name: 'Lord Byron\'s Backribs',
      latitude: 9.3150,
      longitude: 123.3012,
      description: 'Famous local diner serving tender baby back ribs at affordable prices.',
    ),
    FavoritePlaceModel(
      name: 'Gabby\'s Bed and Breakfast Bistro',
      latitude: 9.3175,
      longitude: 123.3005,
      description: 'Quirky retro-themed restaurant offering comfort food and breakfasts.',
    ),
    FavoritePlaceModel(
      name: 'Kri Restaurant',
      latitude: 9.3092,
      longitude: 123.3081,
      description: 'Modern eatery serving Asian-fusion meals, wraps, and gourmet burgers.',
    ),

    // --- Gas & Fuel Stations ---
    FavoritePlaceModel(
      name: 'Petron Gas Station Real St',
      latitude: 9.3021,
      longitude: 123.3045,
      description: 'Petron fuel station with convenience store on Real St.',
    ),
    FavoritePlaceModel(
      name: 'Shell Gas Station North Highway',
      latitude: 9.3198,
      longitude: 123.3049,
      description: 'Shell gasoline and diesel station with Select convenience shop.',
    ),
    FavoritePlaceModel(
      name: 'Caltex Gas Station National Road',
      latitude: 9.2925,
      longitude: 123.2988,
      description: 'Caltex station near Robinsons Mall providing fuel and car wash.',
    ),
    FavoritePlaceModel(
      name: 'SEAOIL Gas Station Valencia',
      latitude: 9.2852,
      longitude: 123.2505,
      description: 'Reliable SEAOIL fuel station along the Dumaguete-Valencia road.',
    ),

    // --- Lodging, Hotels & Suites ---
    FavoritePlaceModel(
      name: 'Hotel Essentia',
      latitude: 9.3095,
      longitude: 123.3090,
      description: 'Premium modern hotel in the heart of Dumaguete commercial center.',
    ),
    FavoritePlaceModel(
      name: 'Coco Grande Hotel',
      latitude: 9.3125,
      longitude: 123.3041,
      description: 'Spanish-Filipino heritage style hotel with comfortable suites.',
    ),
    FavoritePlaceModel(
      name: 'Sierra Hotel',
      latitude: 9.3245,
      longitude: 123.2995,
      description: 'Modern business hotel close to Dumaguete Airport.',
    ),
    FavoritePlaceModel(
      name: 'Rovira Suites',
      latitude: 9.3288,
      longitude: 123.2982,
      description: 'Upscale residential suites and hotel featuring a pool and gardens.',
    ),
    FavoritePlaceModel(
      name: 'Harold\'s Mansion Hostelry',
      latitude: 9.3155,
      longitude: 123.3048,
      description: 'Famous budget backpacker hostel offering tours and rooftop cafe.',
    ),

    // --- Medical & Hospitals ---
    FavoritePlaceModel(
      name: 'Silliman University Medical Center',
      latitude: 9.3130,
      longitude: 123.3045,
      description: 'Primary private training hospital and medical center in Dumaguete.',
    ),
    FavoritePlaceModel(
      name: 'Negros Oriental Provincial Hospital',
      latitude: 9.3225,
      longitude: 123.3021,
      description: 'Main public provincial hospital offering primary and emergency care.',
    ),
    FavoritePlaceModel(
      name: 'Holy Child Hospital',
      latitude: 9.3045,
      longitude: 123.3032,
      description: 'Private community hospital operated by the diocese.',
    ),
    FavoritePlaceModel(
      name: 'Mercury Drug Store Perdices',
      latitude: 9.3071,
      longitude: 123.3092,
      description: '24/7 pharmaceutical and medicine dispensary store.',
    ),

    // --- Shopping, Malls & Plazas ---
    FavoritePlaceModel(
      name: 'Robinsons Place Dumaguete Mall',
      latitude: 9.2942,
      longitude: 123.3005,
      description: 'Major shopping mall featuring retail stores, supermarket, and cinema.',
    ),
    FavoritePlaceModel(
      name: 'Lee Super Plaza',
      latitude: 9.3098,
      longitude: 123.3091,
      description: 'Department store and supermarket located in downtown Dumaguete.',
    ),
    FavoritePlaceModel(
      name: 'CityMall Dumaguete',
      latitude: 9.3375,
      longitude: 123.3015,
      description: 'Convenient shopping center located in the northern area of Dumaguete.',
    ),
    FavoritePlaceModel(
      name: 'Silliman University Main Gate',
      latitude: 9.3120,
      longitude: 123.3075,
      description: 'Historic private research university main entrance.',
    ),
    FavoritePlaceModel(
      name: 'Dumaguete Port Terminal',
      latitude: 9.3117,
      longitude: 123.3128,
      description: 'Seaport connecting Dumaguete to Cebu and other islands.',
    ),
    FavoritePlaceModel(
      name: 'Dumaguete Belfry Tower',
      latitude: 9.3072,
      longitude: 123.3086,
      description: 'Historic stone bell tower built in 1811.',
    ),
  ];

  /// Filters built-in places based on category identifiers.
  static List<FavoritePlaceModel> getPlacesByCategory(String category) {
    final query = category.toLowerCase();
    return builtinPlaces.where((place) {
      final name = place.name.toLowerCase();
      final desc = place.description.toLowerCase();

      switch (query) {
        case 'beaches':
          return name.contains('beach') || desc.contains('beach') || name.contains('sandbar') || desc.contains('sandbar');
        case 'falls':
          return name.contains('falls') || desc.contains('falls') || name.contains('waterfall') || desc.contains('waterfall');
        case 'pools':
          return name.contains('pool') || desc.contains('pool') || name.contains('waterpark') || desc.contains('waterpark');
        case 'springs':
          return name.contains('spring') || desc.contains('spring');
        case 'camps':
          return name.contains('camp') || desc.contains('camp');
        case 'food':
          return name.contains('restaurant') || desc.contains('restaurant') || name.contains('cafe') || desc.contains('cafe') || name.contains('pastries') || name.contains('inato') || name.contains('bar') || name.contains('bistro') || name.contains('diner') || name.contains('eatery');
        case 'gas':
          return name.contains('petron') || name.contains('shell') || name.contains('caltex') || name.contains('seaoil') || name.contains('gas') || desc.contains('gasoline') || desc.contains('fuel');
        case 'lodging':
          return name.contains('hotel') || desc.contains('hotel') || name.contains('resort') || desc.contains('resort') || name.contains('suites') || name.contains('mansion') || name.contains('hostel') || name.contains('bed and breakfast');
        case 'medical':
          return name.contains('medical') || desc.contains('medical') || name.contains('hospital') || desc.contains('hospital') || name.contains('clinic') || name.contains('drug') || name.contains('pharmacy');
        case 'shopping':
          return name.contains('mall') || desc.contains('mall') || name.contains('plaza') || name.contains('super') || name.contains('market') || name.contains('store');
        default:
          return false;
      }
    }).toList();
  }
}
