export default function Home() {
  return (
    <div className="flex flex-col gap-8">
      {/* Hero */}
      <section className="text-center py-12">
        <h2 className="text-4xl font-bold mb-4">
          Private Savings Circles
        </h2>
        <p className="text-gray-400 text-lg max-w-2xl mx-auto">
          Contribute without revealing amounts. Join without exposing identity.
          Your agent coordinates everything.
        </p>
      </section>

      {/* Features */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-gray-900 border border-gray-800 rounded-lg p-6">
          <h3 className="text-shield-500 font-semibold mb-2">🔒 Private Contributions</h3>
          <p className="text-gray-400 text-sm">
            Commit-reveal scheme hides your contribution amount until the round closes.
            No one sees who paid what in real-time.
          </p>
        </div>

        <div className="bg-gray-900 border border-gray-800 rounded-lg p-6">
          <h3 className="text-shield-500 font-semibold mb-2">🆔 ZK Identity</h3>
          <p className="text-gray-400 text-sm">
            Self Protocol proof-of-personhood prevents sybils without
            revealing your personal data.
          </p>
        </div>

        <div className="bg-gray-900 border border-gray-800 rounded-lg p-6">
          <h3 className="text-shield-500 font-semibold mb-2">⭐ Private Reputation</h3>
          <p className="text-gray-400 text-sm">
            Prove you completed N circles with zero defaults — without
            revealing which circles.
          </p>
        </div>

        <div className="bg-gray-900 border border-gray-800 rounded-lg p-6">
          <h3 className="text-shield-500 font-semibold mb-2">🤖 Agent Coordinator</h3>
          <p className="text-gray-400 text-sm">
            AI agent manages circle lifecycle, sends reminders, and executes
            payouts via USDC on Base.
          </p>
        </div>
      </div>

      {/* CTA */}
      <section className="text-center py-8">
        <button className="bg-shield-600 hover:bg-shield-700 text-white px-8 py-3 rounded-lg font-semibold transition-colors">
          Create a Circle
        </button>
        <p className="text-gray-500 text-sm mt-3">
          USDC on Base • Powered by Self Protocol
        </p>
      </section>
    </div>
  );
}
