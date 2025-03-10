import 'package:flutter/material.dart';
import 'package:flutter/material.dart'as m;
import 'package:sqlite3/sqlite3.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Local DB Sync',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
    );
  }
}

class Item {
  final int id;
  final String title;

  Item({required this.id, required this.title});

  Map<String, dynamic> toMap() {
    return {'id': id, 'title': title};
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Database localDb;
  late Database syncDb;
  List<Item> localItems = [];
  List<Item> syncedItems = [];
  bool isSyncing = false;
  final TextEditingController localController = TextEditingController();
  final TextEditingController syncController = TextEditingController();

  @override
  void initState() {
    super.initState();
    initializeDatabases().then((_) {
      loadData();
    });
  }

  /// Initialize two SQLite databases
  Future<void> initializeDatabases() async {
    final directory = await getApplicationDocumentsDirectory();
    final localDbPath = p.join(directory.path, 'local.db');
    final syncDbPath = p.join(directory.path, 'sync.db');

    localDb = sqlite3.open(localDbPath);
    localDb.execute('''  
      CREATE TABLE IF NOT EXISTS local_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT
      );
    ''');

    syncDb = sqlite3.open(syncDbPath);
    syncDb.execute('''  
      CREATE TABLE IF NOT EXISTS sync_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT
      );
    ''');

    loadData();  // Load the data after initializing the databases
  }

  /// Add new item to `local.db`
  void addItem(String title) {
    if (title.isNotEmpty) {
      localDb.execute('INSERT INTO local_items (title) VALUES (?);', [title]);
      loadData();
    }
  }

  /// Add new item to `sync.db`
  void addItemSync(String title) {
    if (title.isNotEmpty) {
      syncDb.execute('INSERT INTO sync_items (title) VALUES (?);', [title]);
      loadData();
    }
  }

  /// Fetch data from `local.db` and `sync.db`
  void loadData() {
    final ResultSet localResult = localDb.select('SELECT id, title FROM local_items ORDER BY id DESC');
    final ResultSet syncResult = syncDb.select('SELECT id, title FROM sync_items ORDER BY id DESC');

    setState(() {
      localItems = localResult
          .map((row) => Item(id: row['id'] as int, title: row['title'] as String))
          .toList();

      syncedItems = syncResult
          .map((row) => Item(id: row['id'] as int, title: row['title'] as String))
          .toList();
    });
  }

  /// Move data from `local.db` to `sync.db` without duplicating existing items
  void syncLocalToSync() {
    setState(() {
      isSyncing = true;
    });

    final ResultSet result = localDb.select('SELECT id, title FROM local_items');
    for (final row in result) {
      final title = row['title'] as String;

      // Check if the title already exists in sync.db before inserting
      final checkResult = syncDb.select('SELECT id FROM sync_items WHERE title = ? LIMIT 1', [title]);
      if (checkResult.isEmpty) {
        syncDb.execute('INSERT INTO sync_items (title) VALUES (?)', [title]);
      }
    }

    loadData();

    setState(() {
      isSyncing = false;
    });

    print("Data synced from local.db to sync.db.");
  }

  /// Move data from `sync.db` to `local.db` without duplicating existing items
  void syncSyncToLocal() {
    setState(() {
      isSyncing = true;
    });

    final ResultSet result = syncDb.select('SELECT id, title FROM sync_items');
    for (final row in result) {
      final title = row['title'] as String;

      // Check if the title already exists in local.db before inserting
      final checkResult = localDb.select('SELECT id FROM local_items WHERE title = ? LIMIT 1', [title]);
      if (checkResult.isEmpty) {
        localDb.execute('INSERT INTO local_items (title) VALUES (?)', [title]);
      }
    }

    loadData();

    setState(() {
      isSyncing = false;
    });

    print("Data synced from sync.db to local.db.");
  }

  @override
  void dispose() {
    localDb.dispose();
    syncDb.dispose();
    localController.dispose();
    syncController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Database Sync'),

      ),
      body: Column(
        children: [
          /// Input Field for Adding Items to Local DB
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: localController,
              onSubmitted: (value) {
                addItem(value);
                localController.clear();
              },
              decoration: const InputDecoration(
                labelText: 'Add Item to Local DB',
                border: OutlineInputBorder(),
              ),
            ),
          ),

          /// Button for Adding Item to Sync DB
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: syncController,
              onSubmitted: (value) {
                addItemSync(value);
                syncController.clear();
              },
              decoration: const InputDecoration(
                labelText: 'Add Item to Sync DB',
                border: OutlineInputBorder(),
              ),
            ),
          ),

          /// Buttons for syncing in both directions
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: m.Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ElevatedButton(
                  onPressed: isSyncing ? null : syncLocalToSync,
                  child: const Text("Sync Local to Sync DB"),
                ),
                ElevatedButton(
                  onPressed: isSyncing ? null : syncSyncToLocal,
                  child: const Text("Sync Sync to Local DB"),
                ),
              ],
            ),
          ),

          /// Display Local Data
          Expanded(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.blueAccent,
                  padding: const EdgeInsets.all(8),
                  child: const Text(
                    "📝 Local Database (Pending Sync)",
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
                Expanded(
                  child: localItems.isEmpty
                      ? const Center(child: Text('No local data available.'))
                      : ListView.builder(
                    itemCount: localItems.length,
                    itemBuilder: (context, index) {
                      final item = localItems[index];
                      return ListTile(
                        leading: Text(item.id.toString()),
                        title: Text(item.title),
                        trailing: const Icon(Icons.hourglass_empty, color: Colors.orange),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          /// Display Synced Data
          Expanded(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.green,
                  padding: const EdgeInsets.all(8),
                  child: const Text(
                    "✅ Synced Database (Final Storage)",
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
                Expanded(
                  child: syncedItems.isEmpty
                      ? const Center(child: Text('No synced data available.'))
                      : ListView.builder(
                    itemCount: syncedItems.length,
                    itemBuilder: (context, index) {
                      final item = syncedItems[index];
                      return ListTile(
                        leading: Text(item.id.toString()),
                        title: Text(item.title),
                        trailing: const Icon(Icons.check_circle, color: Colors.green),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
