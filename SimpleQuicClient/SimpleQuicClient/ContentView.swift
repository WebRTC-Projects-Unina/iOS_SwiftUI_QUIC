//
//  ContentView.swift
//  SimpleQuicClient
//
//  Created by Vincenzo Gerelli on 09/04/26.
//

import SwiftUI

struct ContentView: View {
    @State var vm = ChatManager()
    @State private var text = ""
    @State private var usernameInput = ""
    @State private var showUsernamePrompt = true

    var body: some View {
        VStack(spacing: 12) {
            ConnectionInfoPanel(vm: vm)

            messagesScrollView

            HStack {
                TextField("Write a message…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: text) { _, newValue in
                        // Send a presence notification on every keystroke while the field is non-empty.
                        if !newValue.isEmpty { vm.send("…", type: "presence") }
                    }

                Button("Send") {
                    guard !text.isEmpty else { return }
                    vm.send(text)
                    text = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.isEmpty)
            }
            .padding(.horizontal)

            Button(vm.isConnected ? "Connected" : "Connect") {
                vm.connect()
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isConnected)
        }
        .padding()
        .alert("Enter your name", isPresented: $showUsernamePrompt) {
            TextField("Username", text: $usernameInput)
            Button("OK") { vm.username = usernameInput }
        } message: {
            Text("Your name will be visible to other participants.")
        }
    }

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(vm.messages) { item in
                        MessageBubble(message: item.message, localUsername: vm.username).id(item.id)
                    }
                    ForEach(Array(vm.typingUsers), id: \.self) { user in
                        TypingBubble(username: user)
                    }
                }
            }
            .frame(maxHeight: 320)
            .onChange(of: vm.messages.count) { _, _ in
                if let last = vm.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
