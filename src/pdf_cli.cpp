#include <fwui/fwui.hpp>
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>

using namespace fwui;

static void print_help() {
    std::cout <<
        "Usage: fwui-pdf [options]\n"
        "\n"
        "Options:\n"
        "  -i, --input <file.json>   Input JSON node tree (default: stdin)\n"
        "  -o, --output <file.pdf>   Output PDF file (default: output.pdf, - for stdout)\n"
        "  --page-size <size>        Page size: A4, Letter, A3 (default: A4)\n"
        "  --title <title>           PDF metadata: title\n"
        "  --author <author>         PDF metadata: author\n"
        "  --subject <subject>       PDF metadata: subject\n"
        "  --margins <t,r,b,l>       Page margins in points (default: 72,72,72,72)\n"
        "  --font-size <pt>          Base font size (default: 12)\n"
        "  --page-numbers            Enable automatic page numbering\n"
        "  --page-format <fmt>       Page number format (default: \"Page {page} of {total}\")\n"
        "  -h, --help                Show this help\n"
        "\n"
        "Examples:\n"
        "  echo '{\"tag\":\"h1\",\"text\":\"Hello\"}' | fwui-pdf -i - -o hello.pdf\n"
        "  fwui-pdf -i doc.json -o report.pdf --title \"Report\" --page-numbers\n";
}

static bool parse_margins(const std::string& s, PageMargins& m) {
    std::istringstream iss(s);
    char comma;
    if (!(iss >> m.top >> comma >> m.right >> comma >> m.bottom >> comma >> m.left))
        return false;
    return true;
}

int main(int argc, char* argv[]) {
    std::string input_file = "-";
    std::string output_file = "output.pdf";
    PdfRenderer::Options opts;

    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];

        if ((arg == "-i" || arg == "--input") && i + 1 < argc) {
            input_file = argv[++i];
        } else if ((arg == "-o" || arg == "--output") && i + 1 < argc) {
            output_file = argv[++i];
        } else if (arg == "--page-size" && i + 1 < argc) {
            std::string size = argv[++i];
            if (size == "Letter") opts.page_size = PageSize::Letter();
            else if (size == "A3")  opts.page_size = PageSize::A3();
            else opts.page_size = PageSize::A4(); // default
        } else if (arg == "--title" && i + 1 < argc) {
            opts.title = argv[++i];
        } else if (arg == "--author" && i + 1 < argc) {
            opts.author = argv[++i];
        } else if (arg == "--subject" && i + 1 < argc) {
            opts.subject = argv[++i];
        } else if (arg == "--margins" && i + 1 < argc) {
            if (!parse_margins(argv[++i], opts.margins)) {
                std::cerr << "Invalid margins format. Use: top,right,bottom,left\n";
                return 1;
            }
        } else if (arg == "--font-size" && i + 1 < argc) {
            try { opts.fonts.default_size = std::stof(argv[++i]); }
            catch (...) { std::cerr << "Invalid font size\n"; return 1; }
        } else if (arg == "--page-numbers") {
            opts.auto_page_numbers = true;
        } else if (arg == "--page-format" && i + 1 < argc) {
            opts.page_number_format = argv[++i];
        } else if (arg == "-h" || arg == "--help") {
            print_help();
            return 0;
        } else {
            std::cerr << "Unknown option: " << arg << "\n";
            print_help();
            return 1;
        }
    }

    // Read JSON input
    std::string json_str;
    if (input_file == "-") {
        json_str.assign(std::istreambuf_iterator<char>(std::cin),
                        std::istreambuf_iterator<char>());
    } else {
        std::ifstream in(input_file);
        if (!in) {
            std::cerr << "Cannot open input: " << input_file << "\n";
            return 1;
        }
        json_str.assign(std::istreambuf_iterator<char>(in),
                        std::istreambuf_iterator<char>());
    }

    try {
        auto json = nlohmann::json::parse(json_str);
        auto root = Node::FromJSON(json);
        PdfRenderer renderer(opts);

        if (output_file == "-") {
            auto data = renderer.Render(root);
            std::cout.write(data.data(), static_cast<std::streamsize>(data.size()));
        } else {
            renderer.RenderToFile(root, output_file);
            std::cerr << "Written: " << output_file << "\n";
        }
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
