require 'spec_helper'

describe IssuesFinder do
  set(:user) { create(:user) }
  set(:user2) { create(:user) }
  set(:project1) { create(:project) }
  set(:project2) { create(:project) }
  set(:milestone) { create(:milestone, project: project1) }
  set(:label) { create(:label, project: project2) }
  set(:issue1) { create(:issue, author: user, assignees: [user], project: project1, milestone: milestone, title: 'gitlab', created_at: 1.week.ago) }
  set(:issue2) { create(:issue, author: user, assignees: [user], project: project2, description: 'gitlab') }
  set(:issue3) { create(:issue, author: user2, assignees: [user2], project: project2, title: 'tanuki', description: 'tanuki', created_at: 1.week.from_now) }

  describe '#execute' do
    set(:closed_issue) { create(:issue, author: user2, assignees: [user2], project: project2, state: 'closed') }
    set(:label_link) { create(:label_link, label: label, target: issue2) }
    let(:search_user) { user }
    let(:params) { {} }
    let(:issues) { described_class.new(search_user, params.reverse_merge(scope: scope, state: 'opened')).execute }

    before(:context) do
      project1.team << [user, :master]
      project2.team << [user, :developer]
      project2.team << [user2, :developer]

      issue1
      issue2
      issue3
    end

    context 'scope: all' do
      let(:scope) { 'all' }

      it 'returns all issues' do
        expect(issues).to contain_exactly(issue1, issue2, issue3)
      end

      context 'filtering by assignee ID' do
        let(:params) { { assignee_id: user.id } }

        it 'returns issues assigned to that user' do
          expect(issues).to contain_exactly(issue1, issue2)
        end
      end

      context 'filtering by author ID' do
        let(:params) { { author_id: user2.id } }

        it 'returns issues created by that user' do
          expect(issues).to contain_exactly(issue3)
        end
      end

      context 'filtering by milestone' do
        let(:params) { { milestone_title: milestone.title } }

        it 'returns issues assigned to that milestone' do
          expect(issues).to contain_exactly(issue1)
        end
      end

      context 'filtering by group milestone' do
        let!(:group) { create(:group, :public) }
        let(:group_milestone) { create(:milestone, group: group) }
        let!(:group_member) { create(:group_member, group: group, user: user) }
        let(:params) { { milestone_title: group_milestone.title } }

        before do
          project2.update(namespace: group)
          issue2.update(milestone: group_milestone)
          issue3.update(milestone: group_milestone)
        end

        it 'returns issues assigned to that group milestone' do
          expect(issues).to contain_exactly(issue2, issue3)
        end
      end

      context 'filtering by no milestone' do
        let(:params) { { milestone_title: Milestone::None.title } }

        it 'returns issues with no milestone' do
          expect(issues).to contain_exactly(issue2, issue3)
        end
      end

      context 'filtering by upcoming milestone' do
        let(:params) { { milestone_title: Milestone::Upcoming.name } }

        let(:project_no_upcoming_milestones) { create(:project, :public) }
        let(:project_next_1_1) { create(:project, :public) }
        let(:project_next_8_8) { create(:project, :public) }

        let(:yesterday) { Date.today - 1.day }
        let(:tomorrow) { Date.today + 1.day }
        let(:two_days_from_now) { Date.today + 2.days }
        let(:ten_days_from_now) { Date.today + 10.days }

        let(:milestones) do
          [
            create(:milestone, :closed, project: project_no_upcoming_milestones),
            create(:milestone, project: project_next_1_1, title: '1.1', due_date: two_days_from_now),
            create(:milestone, project: project_next_1_1, title: '8.8', due_date: ten_days_from_now),
            create(:milestone, project: project_next_8_8, title: '1.1', due_date: yesterday),
            create(:milestone, project: project_next_8_8, title: '8.8', due_date: tomorrow)
          ]
        end

        before do
          milestones.each do |milestone|
            create(:issue, project: milestone.project, milestone: milestone, author: user, assignees: [user])
          end
        end

        it 'returns issues in the upcoming milestone for each project' do
          expect(issues.map { |issue| issue.milestone.title }).to contain_exactly('1.1', '8.8')
          expect(issues.map { |issue| issue.milestone.due_date }).to contain_exactly(tomorrow, two_days_from_now)
        end
      end

      context 'filtering by started milestone' do
        let(:params) { { milestone_title: Milestone::Started.name } }

        let(:project_no_started_milestones) { create(:project, :public) }
        let(:project_started_1_and_2) { create(:project, :public) }
        let(:project_started_8) { create(:project, :public) }

        let(:yesterday) { Date.today - 1.day }
        let(:tomorrow) { Date.today + 1.day }
        let(:two_days_ago) { Date.today - 2.days }

        let(:milestones) do
          [
            create(:milestone, project: project_no_started_milestones, start_date: tomorrow),
            create(:milestone, project: project_started_1_and_2, title: '1.0', start_date: two_days_ago),
            create(:milestone, project: project_started_1_and_2, title: '2.0', start_date: yesterday),
            create(:milestone, project: project_started_1_and_2, title: '3.0', start_date: tomorrow),
            create(:milestone, project: project_started_8, title: '7.0'),
            create(:milestone, project: project_started_8, title: '8.0', start_date: yesterday),
            create(:milestone, project: project_started_8, title: '9.0', start_date: tomorrow)
          ]
        end

        before do
          milestones.each do |milestone|
            create(:issue, project: milestone.project, milestone: milestone, author: user, assignees: [user])
          end
        end

        it 'returns issues in the started milestones for each project' do
          expect(issues.map { |issue| issue.milestone.title }).to contain_exactly('1.0', '2.0', '8.0')
          expect(issues.map { |issue| issue.milestone.start_date }).to contain_exactly(two_days_ago, yesterday, yesterday)
        end
      end

      context 'filtering by label' do
        let(:params) { { label_name: label.title } }

        it 'returns issues with that label' do
          expect(issues).to contain_exactly(issue2)
        end
      end

      context 'filtering by multiple labels' do
        let(:params) { { label_name: [label.title, label2.title].join(',') } }
        let(:label2) { create(:label, project: project2) }

        before do
          create(:label_link, label: label2, target: issue2)
        end

        it 'returns the unique issues with any of those labels' do
          expect(issues).to contain_exactly(issue2)
        end
      end

      context 'filtering by no label' do
        let(:params) { { label_name: Label::None.title } }

        it 'returns issues with no labels' do
          expect(issues).to contain_exactly(issue1, issue3)
        end
      end

      context 'filtering by issue term' do
        let(:params) { { search: 'git' } }

        it 'returns issues with title and description match for search term' do
          expect(issues).to contain_exactly(issue1, issue2)
        end
      end

      context 'filtering by issues iids' do
        let(:params) { { iids: issue3.iid } }

        it 'returns issues with iids match' do
          expect(issues).to contain_exactly(issue3)
        end
      end

      context 'filtering by state' do
        context 'with opened' do
          let(:params) { { state: 'opened' } }

          it 'returns only opened issues' do
            expect(issues).to contain_exactly(issue1, issue2, issue3)
          end
        end

        context 'with closed' do
          let(:params) { { state: 'closed' } }

          it 'returns only closed issues' do
            expect(issues).to contain_exactly(closed_issue)
          end
        end

        context 'with all' do
          let(:params) { { state: 'all' } }

          it 'returns all issues' do
            expect(issues).to contain_exactly(issue1, issue2, issue3, closed_issue)
          end
        end

        context 'with invalid state' do
          let(:params) { { state: 'invalid_state' } }

          it 'returns all issues' do
            expect(issues).to contain_exactly(issue1, issue2, issue3, closed_issue)
          end
        end
      end

      context 'filtering by created_at' do
        context 'through created_after' do
          let(:params) { { created_after: issue3.created_at } }

          it 'returns issues created on or after the given date' do
            expect(issues).to contain_exactly(issue3)
          end
        end

        context 'through created_before' do
          let(:params) { { created_before: issue1.created_at + 1.second } }

          it 'returns issues created on or before the given date' do
            expect(issues).to contain_exactly(issue1)
          end
        end
      end

      context 'when the user is unauthorized' do
        let(:search_user) { nil }

        it 'returns no results' do
          expect(issues).to be_empty
        end
      end

      context 'when the user can see some, but not all, issues' do
        let(:search_user) { user2 }

        it 'returns only issues they can see' do
          expect(issues).to contain_exactly(issue2, issue3)
        end
      end

      it 'finds issues user can access due to group' do
        group = create(:group)
        project = create(:project, group: group)
        issue = create(:issue, project: project)
        group.add_user(user, :owner)

        expect(issues).to include(issue)
      end
    end

    context 'personal scope' do
      let(:scope) { 'assigned-to-me' }

      it 'returns issue assigned to the user' do
        expect(issues).to contain_exactly(issue1, issue2)
      end

      context 'filtering by project' do
        let(:params) { { project_id: project1.id } }

        it 'returns issues assigned to the user in that project' do
          expect(issues).to contain_exactly(issue1)
        end
      end
    end

    context 'when project restricts issues' do
      let(:scope) { nil }

      it "doesn't return team-only issues to non team members" do
        project = create(:project, :public, :issues_private)
        issue = create(:issue, project: project)

        expect(issues).not_to include(issue)
      end

      it "doesn't return issues if feature disabled" do
        [project1, project2].each do |project|
          project.project_feature.update!(issues_access_level: ProjectFeature::DISABLED)
        end

        expect(issues.count).to eq 0
      end
    end
  end

  describe '#with_confidentiality_access_check' do
    let(:guest) { create(:user) }
    set(:authorized_user) { create(:user) }
    set(:project) { create(:project, namespace: authorized_user.namespace) }
    set(:public_issue) { create(:issue, project: project) }
    set(:confidential_issue) { create(:issue, project: project, confidential: true) }

    context 'when no project filter is given' do
      let(:params) { {} }

      context 'for an anonymous user' do
        subject { described_class.new(nil, params).with_confidentiality_access_check }

        it 'returns only public issues' do
          expect(subject).to include(public_issue)
          expect(subject).not_to include(confidential_issue)
        end
      end

      context 'for a user without project membership' do
        subject { described_class.new(user, params).with_confidentiality_access_check }

        it 'returns only public issues' do
          expect(subject).to include(public_issue)
          expect(subject).not_to include(confidential_issue)
        end
      end

      context 'for a guest user' do
        subject { described_class.new(guest, params).with_confidentiality_access_check }

        before do
          project.add_guest(guest)
        end

        it 'returns only public issues' do
          expect(subject).to include(public_issue)
          expect(subject).not_to include(confidential_issue)
        end
      end

      context 'for a project member with access to view confidential issues' do
        subject { described_class.new(authorized_user, params).with_confidentiality_access_check }

        it 'returns all issues' do
          expect(subject).to include(public_issue, confidential_issue)
        end
      end
    end

    context 'when searching within a specific project' do
      let(:params) { { project_id: project.id } }

      context 'for an anonymous user' do
        subject { described_class.new(nil, params).with_confidentiality_access_check }

        it 'returns only public issues' do
          expect(subject).to include(public_issue)
          expect(subject).not_to include(confidential_issue)
        end

        it 'does not filter by confidentiality' do
          expect(Issue).not_to receive(:where).with(a_string_matching('confidential'), anything)

          subject
        end
      end

      context 'for a user without project membership' do
        subject { described_class.new(user, params).with_confidentiality_access_check }

        it 'returns only public issues' do
          expect(subject).to include(public_issue)
          expect(subject).not_to include(confidential_issue)
        end

        it 'filters by confidentiality' do
          expect(Issue).to receive(:where).with(a_string_matching('confidential'), anything)

          subject
        end
      end

      context 'for a guest user' do
        subject { described_class.new(guest, params).with_confidentiality_access_check }

        before do
          project.add_guest(guest)
        end

        it 'returns only public issues' do
          expect(subject).to include(public_issue)
          expect(subject).not_to include(confidential_issue)
        end

        it 'filters by confidentiality' do
          expect(Issue).to receive(:where).with(a_string_matching('confidential'), anything)

          subject
        end
      end

      context 'for a project member with access to view confidential issues' do
        subject { described_class.new(authorized_user, params).with_confidentiality_access_check }

        it 'returns all issues' do
          expect(subject).to include(public_issue, confidential_issue)
        end

        it 'does not filter by confidentiality' do
          expect(Issue).not_to receive(:where).with(a_string_matching('confidential'), anything)

          subject
        end
      end
    end
  end
end
