import SwiftUI
import CloudKit

struct DataItemModel: Hashable {
    
    let name: String
    let dataFile: Data?
    let dataFileURL: URL?
    let fileType: String?
    let record: CKRecord
    
}

class CloudKitCRUDViewModel: ObservableObject {
    
    @Published public var text: String = ""
    @Published public var dataItems: [DataItemModel] = []
    @Published public var isDownloading: Bool = false
    
    init() {
        fetchItems()
        
    }
    
    fileprivate func addButtonPressed() {
        guard !text.isEmpty else { return }
        addItem(name: text)
    }
    
    private func addItem(name: String) {
        
        let newRecord = CKRecord(recordType: "DataItems")
        newRecord["name"] = name
        
        guard let url = URL(string: "https://downloadfree3d.com/file/SpvSsnbLrrMfihGNItFf0WHOA5iEDueK5y3OdhFfG5c") else { fatalError() }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let data,
               let response {
                
                print("~~~ Data downloaded")
                
                let fileManager = FileManager.default
                do {
                    let documentDirectory = try fileManager.url(for: .documentDirectory,
                                                                      in: .userDomainMask,
                                                                      appropriateFor: nil,
                                                                      create: false)
                    let url = documentDirectory.appending(path: "archive.zip")
                    
                    print("~~~ URL created: \(url)")
                    
                    do {
                        try data.write(to: url)
                        print("~~~ Data written: \(data.count / 1024 / 1024) Mbs")
                        let asset = CKAsset(fileURL: url)
                        print("~~~ CKAsset created: \(asset.description)")
                        
                        newRecord["dataFile"] = asset
                        if let mimeType = response.mimeType?.description {
                            newRecord["fileType"] = mimeType
                            
                            let newDataItem = DataItemModel(name: name, dataFile: data, dataFileURL: nil, fileType: mimeType, record: newRecord)
                    
                            DispatchQueue.main.async {
                                self.dataItems.append(newDataItem)
                            }
                        }
                        self.saveItem(record: newRecord)
                        
                    } catch {
                        fatalError("~~~ Error writing data to url: \(error.localizedDescription)")
                        
                    }
                    
                } catch {
                    fatalError("~~~ Error getting document directory: \(error)") }
                
            }
            if let error {
                fatalError("~~~ Error downloading zip file: \(error)")
                
            }
        }
        task.resume()
    }
    
    private func saveItem(record: CKRecord) {
        CKContainer.default().publicCloudDatabase.save(record) { [weak self] record, error in
            if let record {
                print("~~~ Record saved: \(record.description)")
            } else if let error {
                print("~~~ Error saving record: \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                self?.text = ""
            }
        }
    }
    
    fileprivate func fetchItems() {
        
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: "DataItems", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let queryOperation = CKQueryOperation(query: query)
        
        var returnedItems: [DataItemModel] = []

        queryOperation.recordMatchedBlock = { (recordID, recordResult) in
            switch recordResult {
                case .success(let record):
                    guard let name = record["name"] as? String else { return }
                    let dataAsset = record["dataFile"] as? CKAsset
                    guard let dataFileURL = dataAsset?.fileURL else { return }
                    let dataFile = try? Data(contentsOf: dataFileURL)
                    
                    let fileType = record["fileType"] as? String
                    let fetchedItem = DataItemModel(name: name, dataFile: dataFile, dataFileURL: dataFileURL, fileType: fileType, record: record)
                    returnedItems.append(DataItemModel(name: name, dataFile: dataFile, dataFileURL: dataFileURL, fileType: fileType, record: record))
                    
                    print("~~~ fetchedItem: \(fetchedItem)")
                    
                    
                case .failure(let error):
                    print("~~~ Error: \(error)")
            }
            
        }
        
        queryOperation.queryResultBlock = { [weak self] result in
            print("~~~ Items fetched from iCloud succesfully")
            DispatchQueue.main.async {
                print("~~~ returnedItems.count: \(returnedItems.count)")
                self?.dataItems = returnedItems
            }
        }
        
        addOperation(operation: queryOperation)
        
    }
    
    private func addOperation(operation: CKDatabaseOperation) {
        CKContainer.default().publicCloudDatabase.add(operation)
        
    }
    
    fileprivate func downloadItem(dataModel: DataItemModel) {

        let predicate = NSPredicate(value: true)

        let query = CKQuery(recordType: "DataItems", predicate: predicate)
        let queryOperation = CKQueryOperation(query: query)
        
        queryOperation.recordMatchedBlock = { (recordID, recordResult) in
            switch recordResult {
                case .success(let record):
                    guard let name = record["name"] as? String else { return }
                    let dataAsset = record["dataFile"] as? CKAsset
                    guard let dataFileURL = dataAsset?.fileURL else { return }
                    let dataFile = try? Data(contentsOf: dataFileURL)
                    
                    let fileType = record["fileType"] as? String
                    let downloadedItem = DataItemModel(name: name,
                                                       dataFile: dataFile,
                                                       dataFileURL: dataFileURL,
                                                       fileType: fileType,
                                                       record: record)
                    
                    if let downloadedData = downloadedItem.dataFile {
                        let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                        
                        if let sharedUrl = URL(string: "shareddocuments://\(documentsUrl.path)") {
                            if UIApplication.shared.canOpenURL(sharedUrl) {
                                DispatchQueue.main.async {
                                    UIApplication.shared.open(sharedUrl, options: [:])
                                }
                            }
                        }
                    }
                    
                    print("~~~ downloadedItem: \(downloadedItem)")
                    
                    DispatchQueue.main.async {
                        self.isDownloading = false
                    }
                case .failure(let error):
                    print("~~~ Error downloading record: \(error)")
            }
        }
        
        queryOperation.queryResultBlock = { result in
            print("~~~ \(result)")
        }
        
        addOperation(operation: queryOperation)
    }
    
    fileprivate func deleteItem(indexSet: IndexSet) {
        
        guard let index = indexSet.first else { return }
        let dataItem = dataItems[index]
        let record = dataItem.record
        
        CKContainer.default().publicCloudDatabase.delete(withRecordID: record.recordID) { [weak self] record, error in
            DispatchQueue.main.async {
                self?.dataItems.remove(at: index)
            }
            if let error {
                print("~~~ Error: \(error)")
            }
        }
    }
    
}

struct CloudKitCRUD: View {
    
    @StateObject private var viewModel = CloudKitCRUDViewModel()
    @State private var selectedItem: DataItemModel?
    @State private var isDownloading: Bool = false {
        willSet {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isDownloading = false
            }
        }
    }
    
    @Environment(\.defaultMinListRowHeight) private var defaultMinListRowHeight: CGFloat
    
    var body: some View {
        NavigationView {
            VStack {
                header
                list
                textField
                addButton
                Spacer(minLength: 20)
                supplementalText
            }
            .padding()
            .navigationBarHidden(true)
        }
    }
}

struct CloudKitCRUD_Previews: PreviewProvider {
    static var previews: some View {
        CloudKitCRUD()
    }
}

extension CloudKitCRUD {
    
    private var header: some View {
        Text("CloudKit Data CRUD")
            .font(.largeTitle)
            .fontDesign(.rounded)
    }
    
    private var list: some View {
        List {
            ForEach(viewModel.dataItems, id: \.self) { dataItem in
                HStack {
                    Button {
                        isDownloading = true
                        selectedItem = dataItem
                        viewModel.downloadItem(dataModel: dataItem)
                    } label: {
                        Text(dataItem.name)
                    }
                    ProgressView()
                        .opacity(isDownloading == true ? 1 : 0)
                }
            }
            .onDelete { indexSet in
                viewModel.deleteItem(indexSet: indexSet)
            }
            .listRowBackground(
                ZStack {
                    LinearGradient(gradient: Gradient(colors: [.clear, .blue, .clear]), startPoint: .leading, endPoint: .trailing)
                        .opacity(isDownloading == true ? 1 : 0)
                        //.mask(Text("Row \(index)").padding()) // Mask the gradient with the text
                        .offset(x: isDownloading == true ? 1000 : -1000) // Initial position off the screen
                        .animation(Animation.easeOut(duration: 0.5), value: isDownloading)
                        .animation(Animation.easeOut(duration: 0.5), value: isDownloading)
                }

            )
            .animation(Animation.easeInOut(duration: 0.3), value: isDownloading)
            
            
        }
        .listStyle(.plain)
    }
    
    private var textField: some View {
        TextField("Name your data file...", text: $viewModel.text)
            .frame(height: UIScreen.main.bounds.height / 18)
            .padding(.leading)
            .background(Color.gray.opacity(0.4))
            .cornerRadius(10)
    }
    
    private var addButton: some View {
        Button {
            viewModel.addButtonPressed()
        } label: {
            Text("Add")
                .frame(height: UIScreen.main.bounds.height / 18)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .background(Color.secondary)
                .cornerRadius(10)
        }
    }
    
    private var supplementalText: some View {
        
        Text(   """
                        Add a new item by giving it a name and tapping 'Add'. The URL is hard-coded but you can customize it.
                        
                        Tap to download or swipe left to delete.
                        """)
        .font(.callout)
        .foregroundColor(.accentColor.opacity(0.5))
    }
    
    
}
