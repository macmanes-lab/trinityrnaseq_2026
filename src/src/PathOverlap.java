
import java.util.*;

public class PathOverlap {
	private final int _stable_hash = StableHash.next();

	public int hashCode() {
		return _stable_hash;
	}


	
	List<Integer> path_A;
	List<Integer> path_B;
	
	int idx_start_A;
	int idx_start_B;
	
	int match_score;
	int match_length;
	
	boolean A_contains_B = false;
	
	public PathOverlap(List<Integer> path_A, List<Integer> path_B, int idx_start_A, int idx_start_B, int score, int length) {
		
		this.path_A = path_A;
		this.path_B = path_B;
		
		this.idx_start_A = idx_start_A;
		this.idx_start_B = idx_start_B;
		
		this.match_score = score;
		this.match_length = length;
	}

	
	public String toString() {
		String ret_text = "pathA:" + path_A +  ", pathB: " + path_B +
				", startA: " + idx_start_A + 
				", startB: " + idx_start_B + 
				", score: " + match_score +
				", match_length: " + match_length + "\n";
				
		return(ret_text);
		
					
	}
	
}
