using System.Text;

namespace AotAnywhere.Tasks;

public static class WindowsRspTokenizer
{
    public static List<string> Tokenize(IEnumerable<string> lines)
    {
        var tokens = new List<string>();
        foreach (var line in lines) TokenizeLine(line, tokens);
        return tokens;
    }

    static void TokenizeLine(string line, List<string> tokens)
    {
        var token = new StringBuilder();
        var inToken = false;
        var inQuotes = false;
        foreach (var character in line)
        {
            if (character == '"')
            {
                inQuotes = !inQuotes;
                inToken = true;
                continue;
            }

            if (!inQuotes && (character == ' ' || character == '\t'))
            {
                if (inToken)
                {
                    tokens.Add(token.ToString());
                    token.Clear();
                    inToken = false;
                }

                continue;
            }

            token.Append(character);
            inToken = true;
        }

        if (inToken) tokens.Add(token.ToString());
    }
}
