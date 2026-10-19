import XCTest
@testable import CodeEdit

final class FileHeaderGeneratorTests: XCTestCase {
    func testSwiftFileHeader() {
        let url = URL(fileURLWithPath: "/Workspace/MyApp/SceneID.swift")
        let date = Date(timeIntervalSince1970: 1678881600)
        let header = FileHeaderGenerator.generateHeader(
            for: url,
            organization: "CodeEdit",
            author: "Wouter Hennen",
            date: date
        )

        let expected = """
        //
        //  SceneID.swift
        //  CodeEdit
        //
        //  Created by Wouter Hennen on 15/03/2023.
        //

        """
        XCTAssertEqual(header, expected)
    }

    func testPHPFileHeader() {
        let url = URL(fileURLWithPath: "/Workspace/MyApp/index.php")
        let date = Date(timeIntervalSince1970: 1678881600)
        let header = FileHeaderGenerator.generateHeader(
            for: url,
            organization: "CodeEdit",
            author: "Wouter Hennen",
            date: date
        )

        let expected = """
        <?php

        //
        //  index.php
        //  CodeEdit
        //
        //  Created by Wouter Hennen on 15/03/2023.
        //

        """
        XCTAssertEqual(header, expected)
    }

    func testPythonFileHeader() {
        let url = URL(fileURLWithPath: "/Workspace/MyApp/script.py")
        let date = Date(timeIntervalSince1970: 1678881600)
        let header = FileHeaderGenerator.generateHeader(
            for: url,
            organization: "MyCompany",
            author: "Test User",
            date: date
        )

        let expected = """
        #
        #  script.py
        #  MyCompany
        #
        #  Created by Test User on 15/03/2023.
        #

        """
        XCTAssertEqual(header, expected)
    }

    func testLuaFileHeader() {
        let url = URL(fileURLWithPath: "/Workspace/MyApp/config.lua")
        let date = Date(timeIntervalSince1970: 1678881600)
        let header = FileHeaderGenerator.generateHeader(
            for: url,
            organization: "GameStudio",
            author: "Developer",
            date: date
        )

        let expected = """
        --
        --  config.lua
        --  GameStudio
        --
        --  Created by Developer on 15/03/2023.
        --

        """
        XCTAssertEqual(header, expected)
    }

    func testHTMLFileHeader() {
        let url = URL(fileURLWithPath: "/Workspace/MyApp/index.html")
        let date = Date(timeIntervalSince1970: 1678881600)
        let header = FileHeaderGenerator.generateHeader(
            for: url,
            organization: "WebOrg",
            author: "Designer",
            date: date
        )

        let expected = """
        <!--
          index.html
          WebOrg

          Created by Designer on 15/03/2023.
        -->

        """
        XCTAssertEqual(header, expected)
    }

    func testDefaultsWhenEmpty() {
        let url = URL(fileURLWithPath: "/Workspace/MyApp/Main.swift")
        let header = FileHeaderGenerator.generateHeader(
            for: url,
            organization: "",
            author: ""
        )

        XCTAssertTrue(header.contains("Main.swift"))
        XCTAssertTrue(header.contains("MyApp"))
        XCTAssertTrue(header.contains("Created by \(NSFullUserName()) on"))
    }
}
