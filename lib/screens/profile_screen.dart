import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('プロフィール'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Signed in as ${user?.displayName}'),
            Text('Email: ${user?.email}'),
            user?.photoURL != null
                ? Image.network(user!.photoURL!)
                : Container(),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                // GoogleSignInインスタンスのsignOutも必要に応じて呼び出す
                // GoogleSignIn().signOut(); 
              },
              child: Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
} 