import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/adoption/animal_page.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Animal> _favorites = [];
  bool _loading = true;

  @override
  void initState(){
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async{
    final uid = FirebaseAuth.instance.currentUser!.uid;
    if(uid == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .get();
    final animals = snapshot.docs.map((doc)
    {
      final data = doc.data();

      return Animal(
        id: data['animalId'],
        name: data['name'],
        breed: data['breed'],
        age: data['age'],
        description: data['description'],
        healthTags: [],
        gender: data['gender'] == 'male'
            ? AnimalGender.male
            : AnimalGender.female,
        category: data['category'] == 'dog'
            ? AnimalCategory.dog
            : AnimalCategory.cat,
        cardColor: AppColors.greenrspwn,
        favorited: true,
        );
      }).toList();

    setState(() {
      _favorites = animals;
      _loading = false;
    });
  }

  Future<void> _toggleFavorite(Animal animal) async{
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if(uid == null) return;

    final favRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(animal.id.toString());

    await favRef.delete();

    setState(() {
      _favorites.removeWhere((a) => a.id == animal.id);
    });
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text('Favorites',
        style: GoogleFonts.tiltWarp(
          fontSize: 22, color:
          AppColors.textPrimary,),
      ),
      ),
      body: _loading
          ? const Center(child:
              CircularProgressIndicator()): _favorites.isEmpty
                ? Center( child:
                    Text('No favorites yet',
                        style: GoogleFonts.zain(fontSize: 16),),
            )
          :ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _favorites.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final animal = _favorites[index];

              return AnimalCard(
                animal: animal,
                onFavorite: () => _toggleFavorite(animal),
                onTap: () {
                   Navigator.push(
                      context,
                        MaterialPageRoute(
                           builder: (context) => AnimalPage(
                             animal: animal,
                             onFavoriteToggle: () =>
                                 _toggleFavorite(animal),
                           ),
                        ),
                    );
                 },
              );
              },
          ),
    );
  }
}