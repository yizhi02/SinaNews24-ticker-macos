import SwiftUI
import AVFoundation
import Foundation
import AppKit

struct SinaNewsItem: Codable {
    let id: Int
    let rich_text: String
    let is_focus: Int?
    let top_value: Int?
    let create_time: String
    let tag: [SinaTag]?
    let multimedia: SinaMultimedia?
    let anchor_image_url: String?
    
    enum CodingKeys: String, CodingKey {
        case id, rich_text, is_focus, top_value, create_time, tag, multimedia, anchor_image_url
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        rich_text = try container.decode(String.self, forKey: .rich_text)
        is_focus = try? container.decode(Int.self, forKey: .is_focus)
        top_value = try? container.decode(Int.self, forKey: .top_value)
        create_time = try container.decode(String.self, forKey: .create_time)
        tag = try? container.decode([SinaTag].self, forKey: .tag)
        anchor_image_url = try? container.decode(String.self, forKey: .anchor_image_url)
        
        // Handle multimedia field which can be string or object
        if let multimediaString = try? container.decode(String.self, forKey: .multimedia) {
            multimedia = SinaMultimedia(img_url: [], string_value: multimediaString)
        } else if let multimediaObj = try? container.decode(SinaMultimedia.self, forKey: .multimedia) {
            multimedia = multimediaObj
        } else {
            multimedia = nil
        }
    }
}

struct SinaMultimedia: Codable {
    let img_url: [String]?
    let string_value: String?
    
    init(img_url: [String]?, string_value: String? = nil) {
        self.img_url = img_url
        self.string_value = string_value
    }
}

struct SinaTag: Codable {
    let id: String
    let name: String
}

struct SinaFeed: Codable {
    let list: [SinaNewsItem]
    let page_info: SinaPageInfo?
}

struct SinaPageInfo: Codable {
    let totalPage: Int
    let pageSize: Int
    let page: Int
    let totalNum: Int
}

struct SinaData: Codable {
    let feed: SinaFeed
}

struct SinaResult: Codable {
    let status: SinaStatus
    let data: SinaData
}

struct SinaStatus: Codable {
    let code: Int
    let msg: String
}

struct SinaAPIResponse: Codable {
    let result: SinaResult
}

struct NewsItem: Codable, Identifiable {
    let id = UUID()
    let text: String
    let is_important: Bool
    let date: String
    let imageURLs: [String]

    private enum CodingKeys: String, CodingKey {
        case text, is_important, date, imageURLs
    }
}

struct ContentView: View {
    @State private var news: [NewsItem] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var currentPage = 1
    @State private var hasMore = true
    @State private var refreshTimer: Timer?
    @State private var broadcastedNewsHashes: Set<String> = []
    @State private var isTTSInProgress: Bool = false
    @State private var speechRate: Double = 0.5
    @State private var previewImage: NSImage? = nil
    @State private var lastKnownItemCount = 0
    private let perPage = 20
    
    private let sinaAPIBaseURL = "https://zhibo.sina.com.cn/api/zhibo/feed"
    private let sinaAPIParams = [
        "zhibo_id": "152",
        "tag": "0",
        "pagesize": "20",
        "dire": "f",
        "dpc": "1"
    ]
    
    init(speechRate: Double = 0.5) {
        self._speechRate = State(initialValue: speechRate)
    }
    
    static let sharedSpeechSynthesizer = AVSpeechSynthesizer()
    
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        return URLSession(configuration: config)
    }()
    

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.0)
                        .tint(.secondary)
                    Text("Loading from Sina API...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.9))
                }
                .padding(24)
                .transition(.scale.combined(with: .opacity))
            } else if news.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("No news loaded")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Button(action: { loadLatestNews() }) {
                        Text("Retry")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.ultraThinMaterial.opacity(0.8))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)
                .transition(.scale.combined(with: .opacity))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(news) { item in
                            NewsRow(item: item, previewImage: $previewImage)
                                .id(item.id)
                        }
                        
                        if hasMore {
                            Color.clear
                                .frame(height: 30)
                                .onAppear {
                                    if !isLoadingMore && hasMore {
                                        self.loadMoreNews()
                                    }
                                }
                        }
                        
                        if isLoadingMore {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.75)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                                Text("Loading more...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary.opacity(0.8))
                            }
                            .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .clipped()
            }
        }
        .frame(width: 365, height: 420)
        .background(LiquidGlassBackground())
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.3),
                            .blue.opacity(0.15),
                            .white.opacity(0.2),
                            .cyan.opacity(0.1),
                            .white.opacity(0.3)
                        ],
                        center: .center
                    ),
                    lineWidth: 0.8
                )
        )
        .onAppear {
            loadLatestNews()
            startOptimizedRefresh()
            debugAvailableVoices()
            
            // Listen for refresh interval changes
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("RefreshIntervalChanged"),
                object: nil,
                queue: .main
            ) { notification in
                if let newInterval = notification.object as? Double {
                    print("🔄 Refresh interval changed to: \(newInterval)s")
                    self.stopPeriodicRefresh()
                    self.startOptimizedRefresh()
                }
            }
        }
        .onDisappear {
            stopPeriodicRefresh()
            ContentView.sharedSpeechSynthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
            print("🧹 ContentView disappeared - cleaned up resources")
        }
        .overlay(
            Group {
                if let previewImage = previewImage {
                    ZStack {
                        Rectangle()
                            .fill(.regularMaterial.opacity(0.95))
                            .background(
                                ZStack {
                                    // Enhanced backdrop with subtle animation
                                    Rectangle()
                                        .fill(
                                            RadialGradient(
                                                colors: [
                                                    .black.opacity(0.02),
                                                    .black.opacity(0.25),
                                                    .black.opacity(0.4)
                                                ],
                                                center: .center,
                                                startRadius: 50,
                                                endRadius: 400
                                            )
                                        )
                                    
                                    // Premium glass blur effect
                                    Rectangle()
                                        .fill(.ultraThinMaterial.opacity(0.3))
                                        .background(
                                            Rectangle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            .white.opacity(0.05),
                                                            .blue.opacity(0.02),
                                                            .clear
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        )
                                }
                            )
                            .ignoresSafeArea(.all)
                        
                        VStack(spacing: 20) {
                            Spacer()
                            
                            Image(nsImage: previewImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 650, maxHeight: 450)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    .white.opacity(0.5),
                                                    .blue.opacity(0.3),
                                                    .white.opacity(0.2),
                                                    .clear
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2.0
                                        )
                                )
                                .shadow(color: .black.opacity(0.2), radius: 30, x: 0, y: 20)
                                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 6)
                                .shadow(color: .white.opacity(0.4), radius: 2, x: 0, y: 1)
                            
                            Spacer()
                            
                            Text("Click anywhere or press ESC to close")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.regularMaterial.opacity(0.8))
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            .white.opacity(0.15),
                                                            .blue.opacity(0.05),
                                                            .clear
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [
                                                            .white.opacity(0.4),
                                                            .white.opacity(0.2),
                                                            .clear
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1.0
                                                )
                                        )
                                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                                        .shadow(color: .white.opacity(0.3), radius: 1, x: 0, y: 1)
                                )
                                .padding(.bottom, 30)
                        }
                    }
                    .onTapGesture {
                        let impactFeedback = NSHapticFeedbackManager.defaultPerformer
                        impactFeedback.perform(.generic, performanceTime: .now)
                        
                        withAnimation(.interpolatingSpring(stiffness: 300, damping: 20)) {
                            self.previewImage = nil
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)).combined(with: .move(edge: .bottom)),
                        removal: .opacity.combined(with: .scale(scale: 0.9)).combined(with: .move(edge: .top))
                    ))
                }
            },
            alignment: .center
        )
    }

    func loadLatestNews() {
        isLoading = true
        
        // Test basic network connectivity first
        testBasicNetworkConnection { success in
            if success {
                self.fetchFromSinaAPI(pageSize: 10) { newsItems in
                    DispatchQueue.main.async {
                        withAnimation(.none) {
                            self.news = newsItems
                        }
                        self.isLoading = false
                        self.currentPage = 1
                        self.hasMore = newsItems.count >= 10
                        
                        // Mark all important news as "seen" to prevent TTS on app open
                        for item in newsItems.filter({ $0.is_important }) {
                            self.broadcastedNewsHashes.insert(self.generateHash(for: item.text))
                        }
                        
                        // Also mark keyword-matching news as "seen" on app open
                        let keywordMatching = self.checkForKeywordMatches(in: newsItems)
                        for item in keywordMatching {
                            self.broadcastedNewsHashes.insert(self.generateHash(for: item.text))
                        }
                        
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func testBasicNetworkConnection(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://httpbin.org/get") else {
            completion(false)
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(false)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                completion(httpResponse.statusCode == 200)
            } else {
                completion(false)
            }
        }
        task.resume()
    }
    
    
    func loadMoreNews() {
        guard !isLoadingMore && hasMore else { 
            return 
        }
        
        isLoadingMore = true
        let nextPage = currentPage + 1
        
        fetchFromSinaAPI(pageSize: perPage, page: nextPage) { newsItems in
            DispatchQueue.main.async {
                self.isLoadingMore = false
                
                if !newsItems.isEmpty {
                    // Filter out duplicates by comparing news text
                    let existingTexts = Set(self.news.map { $0.text })
                    let newItems = newsItems.filter { !existingTexts.contains($0.text) }
                    
                    if !newItems.isEmpty {
                        // Store the old count to detect content changes
                        self.lastKnownItemCount = self.news.count
                        
                        // Append new items without triggering UI updates that could collapse expanded items
                        withAnimation(.none) {
                            self.news.append(contentsOf: newItems)
                        }
                        self.currentPage = nextPage
                        // Continue loading if we got any items (API might return fewer than requested)
                        self.hasMore = newsItems.count > 0
                        
                        print("✅ Load more: Added \(newItems.count) new items (filtered from \(newsItems.count)), total: \(self.news.count), hasMore: \(self.hasMore)")
                    } else {
                        print("⚠️ All items were duplicates, stopping pagination")
                        self.hasMore = false
                    }
                } else {
                    self.hasMore = false
                    print("⚠️ No more items available from API")
                }
            }
        }
    }
    
    private func fetchFromSinaAPI(pageSize: Int = 20, page: Int = 1, completion: @escaping ([NewsItem]) -> Void) {
        guard var urlComponents = URLComponents(string: sinaAPIBaseURL) else {
            print("❌ Invalid Sina API URL")
            completion([])
            return
        }
        
        // Build query parameters
        var queryItems = [URLQueryItem]()
        for (key, value) in sinaAPIParams {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        
        // Override pagesize for this request
        queryItems = queryItems.filter { $0.name != "pagesize" }
        queryItems.append(URLQueryItem(name: "pagesize", value: String(pageSize)))
        
        // Use page-based pagination for Sina API
        if page > 1 {
            queryItems.append(URLQueryItem(name: "page", value: String(page)))
        }
        
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            print("❌ Failed to construct Sina API URL")
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        print("🌐 Fetching from Sina API: \(url.absoluteString)")
        
        urlSession.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Sina API request failed: \(error.localizedDescription)")
                print("❌ Error domain: \(error._domain), code: \(error._code)")
                completion([])
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 HTTP Status: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    print("❌ Non-200 status code: \(httpResponse.statusCode)")
                    completion([])
                    return
                }
            }
            
            guard let data = data else {
                print("❌ No data received from Sina API")
                completion([])
                return
            }
            
            do {
                let apiResponse = try JSONDecoder().decode(SinaAPIResponse.self, from: data)
                
                guard apiResponse.result.status.code == 0 else {
                    print("❌ Sina API error: \(apiResponse.result.status.msg)")
                    completion([])
                    return
                }
                
                let sinaNewsItems = apiResponse.result.data.feed.list
                print("✅ Sina API returned \(sinaNewsItems.count) items for page \(page)")
                
                // Log page info if available
                if let pageInfo = apiResponse.result.data.feed.page_info {
                    print("📄 Page info: page \(pageInfo.page)/\(pageInfo.totalPage), total: \(pageInfo.totalNum)")
                }
                
                // Convert Sina news items to app news items
                let convertedNews = self.convertSinaNewsToAppNews(sinaNewsItems)
                print("✅ Converted \(convertedNews.count) news items")
                completion(convertedNews)
                
            } catch {
                print("❌ Failed to decode Sina API response: \(error)")
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📄 Raw response: \(String(jsonString.prefix(500)))...")
                }
                completion([])
            }
        }.resume()
    }
    
    private func convertSinaNewsToAppNews(_ sinaItems: [SinaNewsItem]) -> [NewsItem] {
        return sinaItems.compactMap { sinaItem in
            // Extract and format the news text exactly like the backend did
            let formattedText = formatNewsText(
                content: sinaItem.rich_text,
                createTime: sinaItem.create_time
            )
            
            // Determine if news is important based on "焦点" tag
            let isImportant = sinaItem.tag?.contains { $0.name == "焦点" } ?? false
            
            // Extract time for date field
            let dateString = extractTimeFromCreateTime(sinaItem.create_time)
            
            // Extract image URLs
            let imageURLs = extractImageURLs(from: sinaItem)
            
            return NewsItem(
                text: formattedText,
                is_important: isImportant,
                date: dateString,
                imageURLs: imageURLs
            )
        }
    }
    
    private func formatNewsText(content: String, createTime: String) -> String {
        // Extract time from create_time
        let timeString = extractTimeFromCreateTime(createTime)
        
        // Format exactly like backend: "HH:MM:SS\n【Title】Content"
        let formattedText = "\(timeString)\n\(content)"
        
        return formattedText
    }
    
    private func extractTimeFromCreateTime(_ createTime: String) -> String {
        // Parse create_time format: "2025-06-28 18:19:51"
        let components = createTime.components(separatedBy: " ")
        if components.count >= 2 {
            return components[1] // Return "18:19:51"
        }
        return "00:00:00"
    }
    
    private func extractImageURLs(from sinaItem: SinaNewsItem) -> [String] {
        var imageURLs: [String] = []
        
        // Extract from anchor_image_url
        if let anchorImageURL = sinaItem.anchor_image_url, !anchorImageURL.isEmpty {
            imageURLs.append(anchorImageURL)
        }
        
        // Extract from multimedia field
        if let multimedia = sinaItem.multimedia {
            // Extract from img_url array if available
            if let imgUrls = multimedia.img_url {
                imageURLs.append(contentsOf: imgUrls)
            }
            
            // If it's a string value, try to parse as JSON
            if let stringValue = multimedia.string_value, !stringValue.isEmpty {
                if let data = stringValue.data(using: .utf8),
                   let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    // Look for image URLs in various possible fields
                    if let images = jsonObject["images"] as? [[String: Any]] {
                        for image in images {
                            if let url = image["url"] as? String {
                                imageURLs.append(url)
                            }
                        }
                    }
                    
                    // Look for img_url array
                    if let imgUrls = jsonObject["img_url"] as? [String] {
                        imageURLs.append(contentsOf: imgUrls)
                    }
                    
                    // Look for single image URL
                    if let imageURL = jsonObject["image"] as? String {
                        imageURLs.append(imageURL)
                    }
                }
            }
        }
        
        // Extract image URLs from rich_text using regex
        let imagePattern = #"https?://[^\s]+\.(jpg|jpeg|png|gif|webp)"#
        if let regex = try? NSRegularExpression(pattern: imagePattern, options: .caseInsensitive) {
            let matches = regex.matches(in: sinaItem.rich_text, range: NSRange(sinaItem.rich_text.startIndex..., in: sinaItem.rich_text))
            for match in matches {
                if let range = Range(match.range, in: sinaItem.rich_text) {
                    imageURLs.append(String(sinaItem.rich_text[range]))
                }
            }
        }
        
        return Array(Set(imageURLs)) // Remove duplicates
    }
    
    func performManualRefresh(completion: (() -> Void)? = nil) {
        fetchFromSinaAPI(pageSize: 10) { newsItems in
            DispatchQueue.main.async {
                withAnimation(.none) {
                    self.news = newsItems
                }
                self.currentPage = 1
                self.hasMore = newsItems.count >= 10
                
                // Play refresh sound
                self.playRefreshSound()
                
                print("✅ Manual refresh: Updated with \(newsItems.count) news items from Sina API")
                completion?()
            }
        }
    }
    
    private func startOptimizedRefresh() {
        // Get refresh interval from UserDefaults, default to 30 seconds
        let interval = UserDefaults.standard.double(forKey: "RefreshInterval")
        let refreshInterval = interval > 0 ? interval : 30.0
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            self.refreshNewsInBackground()
        }
        print("✅ Started refresh timer with interval: \(refreshInterval)s")
    }
    
    private func refreshNewsInBackground() {
        // Prevent multiple simultaneous refresh operations to reduce CPU load
        guard !isLoading && !isLoadingMore else {
            print("⚠️ Background refresh skipped - already loading")
            return
        }
        
        fetchFromSinaAPI(pageSize: 10) { newsItems in
            DispatchQueue.main.async {
                // Check for new important news for TTS
                let newImportantNews = newsItems.filter { item in
                    item.is_important && !self.broadcastedNewsHashes.contains(self.generateHash(for: item.text))
                }
                
                // Check for keyword matches
                let keywordMatchingNews = self.checkForKeywordMatches(in: newsItems)
                
                // Handle new important news
                if !newImportantNews.isEmpty {
                    for item in newImportantNews {
                        self.broadcastedNewsHashes.insert(self.generateHash(for: item.text))
                    }
                    
                    self.playDropletSound()
                    print("🚨 Background: Found \(newImportantNews.count) new important news items for TTS")
                    
                    // Send notifications
                    for newsItem in newImportantNews {
                        let title = self.extractTitle(from: newsItem.text)
                        let content = self.extractMainContent(from: newsItem.text)
                        self.sendNotification(title: title, content: content, isImportant: true)
                    }
                    
                    // TTS after sound - only speak the first important news if enabled
                    let broadcastEnabled = UserDefaults.standard.object(forKey: "ImportantNewsBroadcastEnabled") as? Bool ?? true
                    if broadcastEnabled {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if let firstImportantNews = newImportantNews.first {
                                let broadcastTitle = UserDefaults.standard.object(forKey: "ImportantNewsBroadcastTitle") as? Bool ?? true
                                if broadcastTitle {
                                    self.speakChineseText(firstImportantNews.text)
                                } else {
                                    self.speakChineseFullContent(firstImportantNews.text)
                                }
                            }
                        }
                    }
                }
                
                // Handle keyword matching news
                if !keywordMatchingNews.isEmpty {
                    for item in keywordMatchingNews {
                        self.broadcastedNewsHashes.insert(self.generateHash(for: item.text))
                    }
                    
                    self.playKeywordSound()
                    print("🔍 Background: Found \(keywordMatchingNews.count) keyword-matching news items")
                    
                    // Send notifications
                    for newsItem in keywordMatchingNews {
                        let title = self.extractTitle(from: newsItem.text)
                        let content = self.extractMainContent(from: newsItem.text)
                        let matchedKeyword = self.findMatchingKeyword(in: newsItem.text)
                        self.sendNotification(title: title, content: content, isImportant: false, keyword: matchedKeyword)
                    }
                    
                    // TTS for keyword news - only speak the first one if enabled
                    let keywordBroadcastEnabled = UserDefaults.standard.object(forKey: "KeywordNewsBroadcastEnabled") as? Bool ?? true
                    if keywordBroadcastEnabled {
                        let delay = newImportantNews.isEmpty ? 0.5 : 2.0
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            if let firstKeywordNews = keywordMatchingNews.first {
                                let keywordBroadcastTitle = UserDefaults.standard.object(forKey: "KeywordNewsBroadcastTitle") as? Bool ?? false
                                if keywordBroadcastTitle {
                                    self.speakChineseText(firstKeywordNews.text)
                                } else {
                                    self.speakChineseFullContent(firstKeywordNews.text)
                                }
                            }
                        }
                    }
                }
                
                // Update news list only with new items at the top to preserve scroll position
                let currentHashes = Set(self.news.map { self.generateHash(for: $0.text) })
                let newHashes = Set(newsItems.map { self.generateHash(for: $0.text) })
                
                if currentHashes != newHashes {
                    // Find truly new items (not just reordered)
                    let newItems = newsItems.filter { newItem in
                        !currentHashes.contains(self.generateHash(for: newItem.text))
                    }
                    
                    if !newItems.isEmpty {
                        // Insert new items at the beginning without disrupting scroll
                        withAnimation(.none) {
                            self.news.insert(contentsOf: newItems, at: 0)
                        }
                        print("✅ Background: Added \(newItems.count) new items at top, total: \(self.news.count)")
                    } else {
                        print("ℹ️ Background: No new items to add, keeping current list")
                    }
                }
            }
        }
    }
    
    private func stopPeriodicRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func playDropletSound() {
        let soundName = UserDefaults.standard.string(forKey: "NewsSound") ?? "Submarine"
        if soundName != "None", let sound = NSSound(named: soundName) {
            sound.play()
        }
    }
    
    private func playRefreshSound() {
        let soundName = UserDefaults.standard.string(forKey: "RefreshSound") ?? "Pop"
        if soundName != "None", let sound = NSSound(named: soundName) {
            sound.play()
        }
    }
    
    private func playKeywordSound() {
        let soundName = UserDefaults.standard.string(forKey: "KeywordSound") ?? "Glass"
        if soundName != "None", let sound = NSSound(named: soundName) {
            sound.play()
        }
    }
    
    private func speakChineseText(_ text: String) {
        // Check TTS flag on main thread first (fast check)
        guard !isTTSInProgress else {
            print("⚠️ TTS already in progress (flag: \(isTTSInProgress)), skipping duplicate announcement")
            return
        }
        
        let synthesizer = ContentView.sharedSpeechSynthesizer
        
        let newsTitle = extractTitle(from: text)
        
        guard !newsTitle.isEmpty else { 
            print("⚠️ No title extracted from text: \(String(text.prefix(100)))...")
            return 
        }
        
        print("📢 About to speak title: '\(newsTitle)'")
        
        isTTSInProgress = true
        
        let utterance = AVSpeechUtterance(string: newsTitle)
        
        let bestChineseVoice = getBestChineseVoice()
        utterance.voice = bestChineseVoice
        
        utterance.rate = Float(speechRate)
        utterance.volume = 0.95
        utterance.pitchMultiplier = 1.05
        
        if #available(macOS 13.0, *) {
            utterance.prefersAssistiveTechnologySettings = false
        }
        
        // Stop any existing speech safely
        synthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        
        synthesizer.speak(utterance)
        print("🔊 Speaking Chinese title: \(newsTitle)")
        
        // Calculate dynamic timeout for title (typically shorter)
        let titleLength = newsTitle.count
        let estimatedDuration = max(Double(titleLength) / (speechRate * 120.0) * 60.0, 2.0)
        let timeoutDuration = min(estimatedDuration + 3.0, 15.0) // Cap at 15 seconds for titles
        
        print("📏 Title length: \(titleLength), estimated duration: \(estimatedDuration)s, timeout: \(timeoutDuration)s")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutDuration) {
            self.isTTSInProgress = false
            print("⏰ TTS timeout completed for title")
        }
    }
    
    private func speakChineseFullContent(_ text: String) {
        // Check TTS flag on main thread first (fast check)
        guard !isTTSInProgress else {
            print("⚠️ TTS already in progress (flag: \(isTTSInProgress)), skipping duplicate keyword announcement")
            return
        }
        
        let synthesizer = ContentView.sharedSpeechSynthesizer
        
        let fullContent = extractMainContent(from: text)
        
        guard !fullContent.isEmpty else { return }
        
        isTTSInProgress = true
        
        let utterance = AVSpeechUtterance(string: fullContent)
        
        let bestChineseVoice = getBestChineseVoice()
        utterance.voice = bestChineseVoice
        
        utterance.rate = Float(speechRate)
        utterance.volume = 0.95
        utterance.pitchMultiplier = 1.05
        
        if #available(macOS 13.0, *) {
            utterance.prefersAssistiveTechnologySettings = false
        }
        
        // Stop any existing speech safely
        synthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        
        synthesizer.speak(utterance)
        print("🔊 Speaking keyword-matched full content: \(String(fullContent.prefix(50)))...")
        
        // Calculate dynamic timeout based on content length and speech rate
        // Estimate: ~100 Chinese characters per minute at normal speed
        let contentLength = fullContent.count
        let estimatedDuration = max(Double(contentLength) / (speechRate * 100.0) * 60.0, 5.0)
        let timeoutDuration = min(estimatedDuration + 5.0, 60.0) // Cap at 60 seconds max
        
        print("📏 Content length: \(contentLength), estimated duration: \(estimatedDuration)s, timeout: \(timeoutDuration)s")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutDuration) {
            self.isTTSInProgress = false
            print("⏰ TTS timeout completed for keyword content")
        }
    }
    
    private func getBestChineseVoice() -> AVSpeechSynthesisVoice? {
        let availableVoices = AVSpeechSynthesisVoice.speechVoices()
        
        let preferredVoiceIdentifiers = [
            "com.apple.voice.premium.zh-CN.Tingting",
            "com.apple.voice.enhanced.zh-CN.Tingting",
            "com.apple.voice.compact.zh-CN.Tingting",
            "com.apple.voice.premium.zh-TW.Meijia",
            "com.apple.voice.enhanced.zh-TW.Meijia",
            "com.apple.voice.premium.zh-HK.Sinji",
            "com.apple.voice.enhanced.zh-HK.Sinji"
        ]
        
        for identifier in preferredVoiceIdentifiers {
            if let voice = availableVoices.first(where: { $0.identifier == identifier }) {
                print("✅ Selected premium Chinese voice: \(voice.name) (\(voice.language))")
                return voice
            }
        }
        
        let chineseVoices = availableVoices.filter { $0.language.hasPrefix("zh") }
        
        if let enhancedVoice = chineseVoices.first(where: { $0.quality == .enhanced }) {
            print("✅ Selected enhanced Chinese voice: \(enhancedVoice.name) (\(enhancedVoice.language))")
            return enhancedVoice
        }
        
        if let defaultVoice = chineseVoices.first(where: { $0.language == "zh-CN" }) {
            print("✅ Selected default Chinese voice: \(defaultVoice.name) (\(defaultVoice.language))")
            return defaultVoice
        }
        
        if let anyChineseVoice = chineseVoices.first {
            print("✅ Selected fallback Chinese voice: \(anyChineseVoice.name) (\(anyChineseVoice.language))")
            return anyChineseVoice
        }
        
        print("⚠️ No Chinese voice found, using system default")
        return nil
    }
    
    private func debugAvailableVoices() {
        let availableVoices = AVSpeechSynthesisVoice.speechVoices()
        let chineseVoices = availableVoices.filter { $0.language.hasPrefix("zh") }
        
        print("=== Available Chinese Voices ===")
        for voice in chineseVoices {
            print("Name: \(voice.name), Language: \(voice.language), Quality: \(voice.quality.rawValue)")
        }
        print("Total Chinese voices: \(chineseVoices.count)")
        print("================================")
    }
    
    private func extractTitle(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { 
            // If no newlines, use first part of the text as title
            return String(text.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let contentWithTitle = lines.dropFirst().joined(separator: " ")
        
        // Try to extract title from 【】 brackets first
        if let titleStart = contentWithTitle.firstIndex(of: "【"),
           let titleEnd = contentWithTitle.firstIndex(of: "】") {
            let titleStartIndex = contentWithTitle.index(after: titleStart)
            let title = String(contentWithTitle[titleStartIndex..<titleEnd])
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                return trimmedTitle
            }
        }
        
        // Fallback to first meaningful words
        let words = contentWithTitle.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        if !words.isEmpty {
            return words.prefix(8).joined(separator: " ")
        }
        
        // Last resort: use the full content (truncated)
        return String(contentWithTitle.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractMainContent(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return "" }
        
        let contentWithTitle = lines.dropFirst().joined(separator: " ")
        
        var mainContent = contentWithTitle
        
        if let titleStart = mainContent.firstIndex(of: "【"),
           let titleEnd = mainContent.firstIndex(of: "】") {
            let titleRange = titleStart...titleEnd
            mainContent.removeSubrange(titleRange)
        }
        
        mainContent = mainContent
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return mainContent
    }
    
    private func generateHash(for text: String) -> String {
        let data = text.data(using: .utf8) ?? Data()
        return data.base64EncodedString()
    }
    
    private func checkForKeywordMatches(in newsItems: [NewsItem]) -> [NewsItem] {
        let keywords = UserDefaults.standard.array(forKey: "MonitoredKeywords") as? [String] ?? []
        guard !keywords.isEmpty else { 
            print("ℹ️ No keywords configured for monitoring")
            return [] 
        }
        
        print("🔍 Checking \(newsItems.count) news items against \(keywords.count) keywords: \(keywords)")
        
        return newsItems.filter { item in
            guard !self.broadcastedNewsHashes.contains(self.generateHash(for: item.text)) else { 
                return false 
            }
            
            let newsTextLower = item.text.lowercased()
            for keyword in keywords {
                let keywordLower = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if !keywordLower.isEmpty && newsTextLower.contains(keywordLower) {
                    print("✅ Keyword match found: '\(keyword)' in news: \(String(item.text.prefix(100)))...")
                    return true
                }
            }
            return false
        }
    }
    
    private func findMatchingKeyword(in text: String) -> String {
        let keywords = UserDefaults.standard.array(forKey: "MonitoredKeywords") as? [String] ?? []
        let textLower = text.lowercased()
        
        for keyword in keywords {
            let keywordLower = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !keywordLower.isEmpty && textLower.contains(keywordLower) {
                return keyword
            }
        }
        return "未知关键词"
    }
    
    private func sendNotification(title: String, content: String, isImportant: Bool, keyword: String? = nil) {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            if isImportant {
                appDelegate.sendImportantNewsNotification(title: title, content: content)
            } else if let keyword = keyword {
                appDelegate.sendKeywordNewsNotification(keyword: keyword, title: title, content: content)
            }
        }
    }
}

struct LiquidGlassBackground: View {
    @State private var animateGradient = false
    
    var body: some View {
        ZStack {
            // Base glass layer with enhanced gradient
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial.opacity(0.45))
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            AngularGradient(
                                colors: [
                                    .white.opacity(animateGradient ? 0.12 : 0.08),
                                    .blue.opacity(animateGradient ? 0.05 : 0.02),
                                    .white.opacity(animateGradient ? 0.10 : 0.06),
                                    .cyan.opacity(animateGradient ? 0.03 : 0.015),
                                    .white.opacity(animateGradient ? 0.12 : 0.08)
                                ],
                                center: .center,
                                startAngle: .degrees(animateGradient ? 360 : 0),
                                endAngle: .degrees(animateGradient ? 720 : 360)
                            )
                        )
                )
            
            // Enhanced highlight overlay
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial.opacity(0.3))
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            RadialGradient(
                                colors: [
                                    .white.opacity(0.10),
                                    .white.opacity(0.03),
                                    .clear
                                ],
                                center: UnitPoint(x: 0.3, y: 0.2),
                                startRadius: 25,
                                endRadius: 180
                            )
                        )
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.35),
                            .white.opacity(0.15),
                            .white.opacity(0.05),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 25, x: 0, y: 12)
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
        .shadow(color: .white.opacity(0.5), radius: 1, x: 0, y: 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

struct NewsRow: View {
    let item: NewsItem
    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var loadedImages: [NSImage] = []
    @Binding var previewImage: NSImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(extractFormattedTitle(from: item.text))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(item.is_important ? .red : .primary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            
            if isExpanded {
                Text(extractMainContentOnly(from: item.text))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    
                if isExpanded && !loadedImages.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                        ForEach(loadedImages.indices, id: \.self) { index in
                            Image(nsImage: loadedImages[index])
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                .onTapGesture {
                                    let impactFeedback = NSHapticFeedbackManager.defaultPerformer
                                    impactFeedback.perform(.generic, performanceTime: .now)
                                    
                                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 20)) {
                                        previewImage = loadedImages[index]
                                    }
                                }
                                .onHover { hovering in
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        // Subtle hover effect for images
                                    }
                                }
                                .scaleEffect(1.0)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            
            HStack {
                Text(formatAccurateTime(item.text))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                if !item.imageURLs.isEmpty {
                    Image(systemName: "photo")
                        .font(.system(size: 9, weight: .light))
                        .foregroundStyle(.secondary.opacity(0.35))
                        .help("\(item.imageURLs.count) image\(item.imageURLs.count == 1 ? "" : "s")")
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .background(
            ZStack {
                // Enhanced glass effect with balanced layers
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial.opacity(isHovered ? 0.55 : 0.35))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(isHovered ? 0.15 : 0.08),
                                        .blue.opacity(isHovered ? 0.04 : 0.02),
                                        .white.opacity(isHovered ? 0.10 : 0.05),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                
                // Subtle highlight effect on hover
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(isHovered ? 0.15 : 0.0),
                                .clear
                            ],
                            center: .topLeading,
                            startRadius: 15,
                            endRadius: isHovered ? 70 : 50
                        )
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(isHovered ? 0.4 : 0.2),
                                .white.opacity(isHovered ? 0.25 : 0.12),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHovered ? 1.0 : 0.7
                    )
            )
            .shadow(color: .black.opacity(isHovered ? 0.10 : 0.06), radius: isHovered ? 10 : 6, x: 0, y: isHovered ? 5 : 3)
            .shadow(color: .white.opacity(isHovered ? 0.6 : 0.3), radius: 1, x: 0, y: 1)
        )
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let impactFeedback = NSHapticFeedbackManager.defaultPerformer
            impactFeedback.perform(.generic, performanceTime: .now)
            
            withAnimation(.interpolatingSpring(stiffness: 400, damping: 25)) {
                isExpanded.toggle()
            }
            // Load images when expanding
            if isExpanded {
                loadImagesIfNeeded()
            }
        }
    }
    
    private func extractFormattedTitle(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return text }
        
        let content = lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let titleStart = content.firstIndex(of: "【"),
           let titleEnd = content.firstIndex(of: "】") {
            let titleStartIndex = content.index(after: titleStart)
            let title = String(content[titleStartIndex..<titleEnd])
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let words = content.components(separatedBy: " ")
        return words.prefix(8).joined(separator: " ")
    }
    
    private func extractMainContentOnly(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return "" }
        
        let content = lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        
        var mainContent = content
        
        if let titleStart = mainContent.firstIndex(of: "【"),
           let titleEnd = mainContent.firstIndex(of: "】") {
            let titleRange = titleStart...titleEnd
            mainContent.removeSubrange(titleRange)
        }
        
        mainContent = mainContent
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return mainContent.isEmpty ? "No additional content" : mainContent
    }
    
    private func formatAccurateTime(_ originalText: String) -> String {
        let lines = originalText.components(separatedBy: "\n")
        guard let firstLine = lines.first else { return "00:00:00" }
        
        let timePattern = #"^(\d{2}:\d{2}:\d{2})"#
        if let regex = try? NSRegularExpression(pattern: timePattern),
           let match = regex.firstMatch(in: firstLine, range: NSRange(firstLine.startIndex..., in: firstLine)) {
            let timeRange = Range(match.range(at: 1), in: firstLine)!
            return String(firstLine[timeRange])
        }
        
        return "00:00:00"
    }
    
    private func loadImagesIfNeeded() {
        guard loadedImages.isEmpty && !item.imageURLs.isEmpty else { return }
        
        Task {
            var images: [NSImage] = []
            
            for urlString in item.imageURLs.prefix(6) { // Limit to 6 images
                if let url = URL(string: urlString) {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        if let nsImage = NSImage(data: data) {
                            images.append(nsImage)
                        }
                    } catch {
                        print("⚠️ Failed to load image: \(urlString)")
                    }
                }
            }
            
            await MainActor.run {
                self.loadedImages = images
            }
        }
    }
}